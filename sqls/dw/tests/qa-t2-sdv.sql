-- Phase 3 / T2 QA — SDV 合成数据入库与断言
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §8.1(T2) / §9 Phase 3
--
-- 前置：先跑 sqls/dw/scripts/sdv_gen.py 生成 CSV，再由 qa-t2-sdv.sh 完成入库。
-- 判定：所有 T2-* 行必须为 PASS。
--
-- 入库落在 staging 表而非直接进业务表：SDV 产出的值不可预知，若混入 payment
-- 会破坏 T1 夹具的"值可预期"前提，也会污染各层对账基线。

\set ON_ERROR_STOP off

\echo '===== T2-1  合成数据已入 staging ====='
-- 期望行数由驱动通过 -v expected_rows 传入，不可硬编码：
-- 采样规模是 qa-t2-sdv.sh 的 --rows 参数，硬编码会让非默认规模的运行误报失败。
SELECT CASE WHEN count(*) = :expected_rows
            THEN 'T2-1 PASS (' || count(*) || ' 行)'
            ELSE 'T2-1 FAIL (' || count(*) || ' 行, 期望 ' || :expected_rows || ')' END AS result
  FROM dw.stg_sdv_payment;

\echo '===== T2-2  Inequality 约束在库内仍然成立 ====='
SELECT CASE WHEN count(*) = 0 THEN 'T2-2 PASS (return_date > rental_date 无违反)'
            ELSE 'T2-2 FAIL (' || count(*) || ' 行违反)' END AS result
  FROM dw.stg_sdv_rental
 WHERE return_date IS NOT NULL AND return_date <= rental_date;

\echo '===== T2-3  金额档位保真：合成取值必须是真实档位的子集 ====='
SELECT CASE WHEN count(*) = 0 THEN 'T2-3 PASS (合成金额全部落在真实档位上)'
            ELSE 'T2-3 FAIL (' || count(*) || ' 个档位外取值)' END AS result
  FROM (SELECT DISTINCT amount FROM dw.stg_sdv_payment) s
 WHERE NOT EXISTS (SELECT 1 FROM payment p
                    WHERE p.payment_id < 900000000 AND p.amount = s.amount);

\echo '===== T2-4  金额分布保真：中位数与均值偏差在容限内 ====='
SELECT CASE WHEN abs(syn_med - seed_med) < 0.01
             AND abs(syn_avg - seed_avg) / seed_avg < 0.05
            THEN 'T2-4 PASS (中位数一致，均值偏差 '
                 || round(100 * abs(syn_avg - seed_avg) / seed_avg, 2) || '% < 5%)'
            ELSE 'T2-4 FAIL (seed med=' || seed_med || ' avg=' || round(seed_avg,4)
                 || ' vs synth med=' || syn_med || ' avg=' || round(syn_avg,4) || ')' END AS result
  FROM (SELECT (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY amount)
                  FROM payment WHERE payment_id < 900000000)      AS seed_med,
               (SELECT avg(amount) FROM payment WHERE payment_id < 900000000) AS seed_avg,
               (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY amount)
                  FROM dw.stg_sdv_payment)                        AS syn_med,
               (SELECT avg(amount) FROM dw.stg_sdv_payment)       AS syn_avg) t;

\echo '===== T2-5  时间范围被种子数据锁死（SDV 社区版的已知边界）====='
-- enforce_min_max_values=True 使合成日期不会超出种子范围。这正是 SDV 社区版
-- 无法产出"跨多年"数据的原因，也是 T3 规模造数必须用 SQL 侧实现的依据。
SELECT CASE WHEN syn_min >= seed_min AND syn_max <= seed_max
            THEN 'T2-5 PASS (合成时间范围 ⊆ 种子范围，证实社区版无法外推跨度)'
            ELSE 'T2-5 FAIL' END AS result
  FROM (SELECT (SELECT min(payment_date) FROM payment WHERE payment_id < 900000000) AS seed_min,
               (SELECT max(payment_date) FROM payment WHERE payment_id < 900000000) AS seed_max,
               (SELECT min(payment_date) FROM dw.stg_sdv_payment) AS syn_min,
               (SELECT max(payment_date) FROM dw.stg_sdv_payment) AS syn_max) t;

\echo '===== T2-6  未污染业务表与 T1 夹具基线 ====='
SELECT CASE WHEN (SELECT count(*) FROM payment WHERE payment_id < 900000000) = 16049
             AND (SELECT count(*) FROM payment WHERE payment_id >= 900000000
                                                 AND payment_id < 1000000000) = 1624
            THEN 'T2-6 PASS (base 16049 + T1 1624 未变)'
            ELSE 'T2-6 FAIL' END AS result;

\echo '===== 分布对照明细 ====='
SELECT s.amount,
       s.synth_cnt,
       round(100.0 * s.synth_cnt / (SELECT count(*) FROM dw.stg_sdv_payment), 2) AS synth_pct,
       b.seed_cnt,
       round(100.0 * b.seed_cnt / (SELECT count(*) FROM payment WHERE payment_id < 900000000), 2)
         AS seed_pct
  FROM (SELECT amount, count(*) AS synth_cnt FROM dw.stg_sdv_payment GROUP BY amount) s
  FULL JOIN (SELECT amount, count(*) AS seed_cnt FROM payment
              WHERE payment_id < 900000000 GROUP BY amount) b ON b.amount = s.amount
 ORDER BY COALESCE(b.seed_cnt, 0) DESC LIMIT 8;
