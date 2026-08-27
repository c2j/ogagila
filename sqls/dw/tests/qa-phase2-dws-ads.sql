-- Phase 2 QA — Q2.1 ~ Q2.8（DWS + C1/C2/C3）
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §9 Phase 2
--
-- 前置：已加载夹具，已建 DIM/DWD/DWS/ADS。
-- 判定：所有 Q2.* 行必须为 PASS。
-- Q2.7（C1 刷新期间并发读不中断）需两个会话，见 qa-phase2-c1-concurrent.sh。

\set ON_ERROR_STOP off

\echo '===== Q2.1  DWS 幂等：同参数连续 3 次结果一致 ====='
DECLARE
    v_rows integer; v_status varchar2(16);
    v_c1 bigint; v_a1 numeric; v_c2 bigint; v_a2 numeric; v_c3 bigint; v_a3 numeric;
BEGIN
    dw.pkg_dws.build_sales_day_category(date '2025-03-01', date '2025-04-01', 'R_Q21', v_rows, v_status);
    SELECT count(*), COALESCE(sum(amount),0) INTO v_c1, v_a1 FROM dw.dws_sales_day_store_category
      WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01';
    dw.pkg_dws.build_sales_day_category(date '2025-03-01', date '2025-04-01', 'R_Q21', v_rows, v_status);
    SELECT count(*), COALESCE(sum(amount),0) INTO v_c2, v_a2 FROM dw.dws_sales_day_store_category
      WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01';
    dw.pkg_dws.build_sales_day_category(date '2025-03-01', date '2025-04-01', 'R_Q21', v_rows, v_status);
    SELECT count(*), COALESCE(sum(amount),0) INTO v_c3, v_a3 FROM dw.dws_sales_day_store_category
      WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01';

    IF v_c1 = v_c2 AND v_c2 = v_c3 AND v_a1 = v_a2 AND v_a2 = v_a3 THEN
        RAISE NOTICE 'Q2.1 PASS (rows=%, amount=% across 3 runs)', v_c1, v_a1;
    ELSE
        RAISE NOTICE 'Q2.1 FAIL (%/%/% rows, %/%/% amounts)', v_c1,v_c2,v_c3, v_a1,v_a2,v_a3;
    END IF;
END;
/

\echo '===== Q2.2  DWS 与 DWD 逐月对账必须 0 差异 ====='
SELECT CASE WHEN count(*) = 0 THEN 'Q2.2 PASS (逐月对账 0 差异)'
            ELSE 'Q2.2 FAIL (' || count(*) || ' 个月不一致)' END AS result
  FROM (SELECT COALESCE(d.m, s.m) AS m
          FROM (SELECT date_trunc('month', stat_date) m, sum(pay_cnt) c, sum(amount) a
                  FROM dw.dws_sales_day_store_category GROUP BY 1) s
          FULL JOIN (SELECT date_trunc('month', stat_date) m, count(*) c, sum(amount) a
                       FROM dw.dwd_fact_payment WHERE is_within_cutoff GROUP BY 1) d
                 ON d.m = s.m
         WHERE COALESCE(d.c,-1) <> COALESCE(s.c,-1)
            OR COALESCE(d.a,-1) <> COALESCE(s.a,-1)) t;

\echo '===== Q2.3  C3 环比：不完整期必须返回 NULL ====='
SELECT CASE WHEN count(*) = 0 THEN 'Q2.3 PASS (不完整期无环比/同比值)'
            ELSE 'Q2.3 FAIL (' || count(*) || ' 行违规)' END AS result
  FROM dw.v_ads_exec_month_trend
 WHERE NOT is_complete_period AND (mom_pct IS NOT NULL OR yoy_pct IS NOT NULL);

\echo '===== Q2.4  C3 缺月不错位：骨架保证连续月份 ====='
SELECT CASE WHEN count(*) = 0 THEN 'Q2.4 PASS (无月份跳跃)'
            ELSE 'Q2.4 FAIL (' || count(*) || ' 处跳跃)' END AS result
  FROM (SELECT stat_month,
               LAG(stat_month) OVER (PARTITION BY store_id ORDER BY stat_month) AS prev_m
          FROM dw.v_ads_exec_month_trend) t
 WHERE prev_m IS NOT NULL
   AND stat_month <> (prev_m + interval '1 month')::date;

\echo '===== Q2.5  C3 同比：32 月跨度下必须有非 NULL 同比 ====='
SELECT CASE WHEN count(*) > 0 THEN 'Q2.5 PASS (' || count(*) || ' 行有同比)'
            ELSE 'Q2.5 FAIL (同比全为 NULL)' END AS result
  FROM dw.v_ads_exec_month_trend WHERE yoy_pct IS NOT NULL;

\echo '===== Q2.6  C2 GROUPING() 小计层级正确且总计对账 ====='
SELECT CASE WHEN (SELECT count(DISTINCT grain) FROM dw.v_ads_ops_sales_drill) = 4
             AND (SELECT amount FROM dw.v_ads_ops_sales_drill WHERE grain = '总计')
                 = (SELECT sum(amount) FROM dw.dws_sales_day_store_category
                     WHERE store_status = 'ACTIVE')
            THEN 'Q2.6 PASS (4 个粒度 + 总计对账一致)' ELSE 'Q2.6 FAIL' END AS result;

\echo '===== Q2.8  失败重跑无重复：中断后原参数重跑 ====='
DECLARE
    v_rows integer; v_status varchar2(16); v_dup bigint;
BEGIN
    -- 模拟"上次跑到一半"：手工插入半份数据后原参数重跑，结果必须无重复。
    INSERT INTO dw.dws_sales_day_store_category(
        stat_date, store_id, store_status, category_id, category_name,
        pay_cnt, amount, customer_cnt, multi_cat_cnt, dq_flag, run_id)
    SELECT stat_date, store_id, store_status, category_id, category_name,
           pay_cnt, amount, customer_cnt, multi_cat_cnt, dq_flag, 'R_PARTIAL'
      FROM dw.dws_sales_day_store_category
     WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01';

    dw.pkg_dws.build_sales_day_category(date '2025-03-01', date '2025-04-01',
                                        'R_Q28', v_rows, v_status);

    SELECT count(*) INTO v_dup FROM (
        SELECT stat_date, store_id, category_id FROM dw.dws_sales_day_store_category
         WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01'
         GROUP BY 1,2,3 HAVING count(*) > 1) t;

    IF v_dup = 0 THEN
        RAISE NOTICE 'Q2.8 PASS (半成品被 DELETE 清除，重跑无重复)';
    ELSE
        RAISE NOTICE 'Q2.8 FAIL (% 组重复)', v_dup;
    END IF;
END;
/

\echo '===== 补充：C1 大屏 HyperLogLog 近似 UV 与精确值一致性 ====='
SELECT CASE WHEN count(*) = 0 THEN 'c1-hll PASS (近似 UV 与精确值偏差在容限内)'
            ELSE 'c1-hll FAIL (' || count(*) || ' 行偏差过大)' END AS result
  FROM dw.ads_screen_store_today
 WHERE exact_customer_cnt > 0
   AND abs(approx_uv - exact_customer_cnt) > greatest(1, exact_customer_cnt * 0.05);

\echo '===== 清理 ====='
DELETE FROM dw.etl_run_log WHERE run_id LIKE 'R_Q2%';
SELECT 'cleanup PASS' AS result;
