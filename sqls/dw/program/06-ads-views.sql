-- Phase 2 — ADS 应用层视图（C2 中层 / C3 高层）
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §4.3
-- 口径依据：sqls/dw/docs/metric-definitions.md §1 §3 §5 §8 §9 §11
--
-- C2/C3 是**视图**而非物理表：它们是 DWS 之上的口径映射，零维护成本、
-- 口径调整立刻生效。物理化只在 C1 大屏（延迟敏感）与 C4 披露（需冻结）时才做。
--
-- dq_flag 必须透出（§11 闸门语义）：C1/C2/C3 允许"带瑕疵可用"，
-- 但必须让使用者看到瑕疵标记；只有 C4 披露是硬阻塞。

\set ON_ERROR_STOP on

-- C2 中层：多维下钻。用 GROUPING SETS 一次算出"日×店×品类 / 日×店 / 日 / 总计"
-- 四个粒度，比建四张汇总表干净。GROUPING() 标识每行属于哪个小计层级 ——
-- 二者在本实例均已实测可用（官方文档未记载 GROUPING()，实测支持）。
CREATE OR REPLACE VIEW dw.v_ads_ops_sales_drill AS
SELECT stat_date,
       store_id,
       category_name,
       GROUPING(stat_date)     AS g_date,
       GROUPING(store_id)      AS g_store,
       GROUPING(category_name) AS g_category,
       CASE GROUPING(stat_date) + GROUPING(store_id) + GROUPING(category_name)
            WHEN 0 THEN '日x店x品类'
            WHEN 1 THEN '日x店'
            WHEN 2 THEN '日'
            ELSE        '总计' END AS grain,
       sum(pay_cnt)      AS pay_cnt,
       sum(amount)       AS amount,
       sum(customer_cnt) AS customer_cnt_sum,
       bool_or(dq_flag)  AS dq_flag
  FROM dw.dws_sales_day_store_category
 WHERE store_status = 'ACTIVE'
 GROUP BY GROUPING SETS ((stat_date, store_id, category_name),
                         (stat_date, store_id),
                         (stat_date),
                         ());

-- C2 员工人效。store_status='ACTIVE' 过滤是 RK1 的强制约束：
-- 禁止任何层直接 FROM store，门店口径一律来自 dim_store 派生的 store_status。
CREATE OR REPLACE VIEW dw.v_ads_ops_staff_perf AS
SELECT s.stat_date, s.store_id, s.staff_id,
       ds.full_name AS staff_name,
       s.pay_cnt, s.amount,
       CASE WHEN s.pay_cnt > 0 THEN round(s.amount / s.pay_cnt, 2) END AS avg_ticket,
       s.dq_flag
  FROM dw.dws_sales_day_store_staff s
  LEFT JOIN dw.dim_staff ds ON ds.staff_id = s.staff_id
 WHERE s.store_status = 'ACTIVE';

CREATE OR REPLACE VIEW dw.v_ads_ops_rental_health AS
SELECT stat_date, store_id, rental_cnt, returned_cnt, open_cnt, overdue_cnt,
       max_overdue_d,
       CASE WHEN rental_cnt > 0
            THEN round(100.0 * overdue_cnt / rental_cnt, 2) END AS overdue_pct,
       dq_flag
  FROM dw.dws_rental_day_store
 WHERE store_status = 'ACTIVE';

-- C3 高层：月度趋势 + 环比 + 同比。
--
-- 三处正确性要点（口径文档 §3 §9 §10，均有实测依据）：
--   1) **必须先生成"完整月份骨架 × ACTIVE 门店"再 LEFT JOIN 事实**。直接对事实表
--      LAG 会在缺月时静默错位 —— 把 1 月当作 3 月的上一月。
--   2) **不完整期间的环比/同比一律返回 NULL**。实测 2022-02 相对 2022-01 的裸 MoM
--      是 +228.46%（因 1 月仅 23–31 日有数据），这类假暴增进入高层决策即是灾难。
--   3) **严禁 COALESCE(prev, 0)**：会产出 +∞% / -100%。除法一律 NULLIF 保护。
CREATE OR REPLACE VIEW dw.v_ads_exec_month_trend AS
WITH bounds AS (
    SELECT min(stat_month) AS mn, max(stat_month) AS mx FROM dw.dws_sales_month_store
),
skeleton AS (
    SELECT g::date AS stat_month, s.store_id
      FROM bounds b,
           generate_series(b.mn, b.mx, interval '1 month') g
      CROSS JOIN (SELECT DISTINCT store_id FROM dw.dws_sales_month_store
                   WHERE store_status = 'ACTIVE') s
),
fact AS (
    SELECT k.stat_month, k.store_id,
           COALESCE(m.pay_cnt, 0)      AS pay_cnt,
           COALESCE(m.amount, 0)       AS amount,
           COALESCE(m.customer_cnt, 0) AS customer_cnt,
           COALESCE(m.is_complete_period, false) AS is_complete_period,
           COALESCE(m.dq_flag, false)  AS dq_flag,
           m.stat_month IS NULL        AS is_gap_month
      FROM skeleton k
      LEFT JOIN dw.dws_sales_month_store m
             ON m.stat_month = k.stat_month AND m.store_id = k.store_id
            AND m.store_status = 'ACTIVE'
)
SELECT stat_month, store_id, pay_cnt, amount, customer_cnt,
       is_complete_period, is_gap_month, dq_flag,
       LAG(amount, 1)  OVER w AS prev_month_amount,
       LAG(amount, 12) OVER w AS prev_year_amount,
       CASE WHEN is_complete_period
                 AND LAG(is_complete_period, 1) OVER w
            THEN round(100.0 * (amount - LAG(amount, 1) OVER w)
                       / NULLIF(LAG(amount, 1) OVER w, 0), 2) END AS mom_pct,
       CASE WHEN is_complete_period
                 AND LAG(is_complete_period, 12) OVER w
            THEN round(100.0 * (amount - LAG(amount, 12) OVER w)
                       / NULLIF(LAG(amount, 12) OVER w, 0), 2) END AS yoy_pct,
       round(AVG(amount) OVER (PARTITION BY store_id ORDER BY stat_month
                               ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS ma3_amount
  FROM fact
WINDOW w AS (PARTITION BY store_id ORDER BY stat_month);

-- C3 品类 TOP N。⚠️ 品类维度的金额归属规则待业务方按口径文档 §5-B5 裁定
-- （实测 964/1000 部影片属于多个品类，当前取 min(category_id) 单一归属）。
-- **B5 裁定前本视图不得用于对外披露（C4）**。
CREATE OR REPLACE VIEW dw.v_ads_exec_category_rank AS
SELECT stat_month, category_name, pay_cnt, amount,
       RANK()       OVER (PARTITION BY stat_month ORDER BY amount DESC) AS amount_rank,
       DENSE_RANK() OVER (PARTITION BY stat_month ORDER BY pay_cnt DESC) AS cnt_rank,
       round(100.0 * amount / NULLIF(SUM(amount) OVER (PARTITION BY stat_month), 0), 2)
         AS amount_share_pct,
       dq_flag
  FROM (SELECT date_trunc('month', stat_date)::date AS stat_month,
               category_name, sum(pay_cnt) AS pay_cnt, sum(amount) AS amount,
               bool_or(dq_flag) AS dq_flag
          FROM dw.dws_sales_day_store_category
         WHERE store_status = 'ACTIVE'
         GROUP BY 1, 2) t;

SELECT 'ads views' AS component,
       CASE WHEN count(*) = 5 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/5)' END AS result,
       string_agg(viewname, ', ' ORDER BY viewname) AS detail
FROM pg_views WHERE schemaname = 'dw' AND viewname LIKE 'v_ads_%';
