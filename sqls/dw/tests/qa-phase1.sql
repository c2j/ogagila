-- Phase 1 QA — Q1.2 ~ Q1.10
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §9 Phase 1
--
-- 前置：已加载 t1-deterministic.sql；已跑 PKG_DIM.build_all 与 PKG_DWD 全量构建。
-- Q1.1（CV1~CV14 覆盖率）在独立脚本 cv-assertions.sql 中。
-- 判定：所有 result 列必须为 PASS。

\set ON_ERROR_STOP off

\echo '===== Q1.2  夹具跨度满足 YoY（>= 25 个月）====='
SELECT CASE WHEN count(DISTINCT date_trunc('month', payment_date)) >= 25
            THEN 'Q1.2 PASS (' || count(DISTINCT date_trunc('month', payment_date)) || ' months)'
            ELSE 'Q1.2 FAIL' END AS result
  FROM payment WHERE payment_id >= 900000000;

\echo '===== Q1.3  DWD 幂等：同参数连续 3 次结果一致 ====='
DECLARE
    v_rows integer; v_status varchar2(16);
    v_c1 bigint; v_s1 numeric; v_c2 bigint; v_s2 numeric; v_c3 bigint; v_s3 numeric;
BEGIN
    dw.pkg_dwd.build_dwd_fact_payment(date '2025-03-01', date '2025-04-01', 'R_Q13', v_rows, v_status);
    SELECT count(*), COALESCE(sum(amount),0) INTO v_c1, v_s1 FROM dw.dwd_fact_payment
      WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01';
    dw.pkg_dwd.build_dwd_fact_payment(date '2025-03-01', date '2025-04-01', 'R_Q13', v_rows, v_status);
    SELECT count(*), COALESCE(sum(amount),0) INTO v_c2, v_s2 FROM dw.dwd_fact_payment
      WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01';
    dw.pkg_dwd.build_dwd_fact_payment(date '2025-03-01', date '2025-04-01', 'R_Q13', v_rows, v_status);
    SELECT count(*), COALESCE(sum(amount),0) INTO v_c3, v_s3 FROM dw.dwd_fact_payment
      WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01';

    IF v_c1 = v_c2 AND v_c2 = v_c3 AND v_s1 = v_s2 AND v_s2 = v_s3 THEN
        RAISE NOTICE 'Q1.3 PASS (rows=%, sum=% across 3 runs)', v_c1, v_s1;
    ELSE
        RAISE NOTICE 'Q1.3 FAIL (%/%/% rows, %/%/% sums)', v_c1, v_c2, v_c3, v_s1, v_s2, v_s3;
    END IF;
END;
/

\echo '===== Q1.4  增量 vs 全量：双向 EXCEPT 必须为 0 ====='
DROP TABLE IF EXISTS tmp_dwd_full;
CREATE TEMP TABLE tmp_dwd_full AS
SELECT stat_date, payment_id, store_id, store_status, category_id, amount,
       is_within_cutoff, dq_flag
  FROM dw.dwd_fact_payment
 WHERE stat_date >= '2024-01-01' AND stat_date < '2025-01-01';

DECLARE
    v_rows integer; v_status varchar2(16); v_m date;
BEGIN
    DELETE FROM dw.dwd_fact_payment
     WHERE stat_date >= '2024-01-01' AND stat_date < '2025-01-01';
    v_m := date '2024-01-01';
    WHILE v_m < date '2025-01-01' LOOP
        dw.pkg_dwd.build_dwd_fact_payment(v_m, (v_m + interval '1 month')::date,
                                          'R_Q14', v_rows, v_status);
        v_m := (v_m + interval '1 month')::date;
    END LOOP;
END;
/

SELECT CASE WHEN (SELECT count(*) FROM (
                    SELECT * FROM tmp_dwd_full
                    EXCEPT
                    SELECT stat_date, payment_id, store_id, store_status, category_id, amount,
                           is_within_cutoff, dq_flag
                      FROM dw.dwd_fact_payment
                     WHERE stat_date >= '2024-01-01' AND stat_date < '2025-01-01') a) = 0
             AND (SELECT count(*) FROM (
                    SELECT stat_date, payment_id, store_id, store_status, category_id, amount,
                           is_within_cutoff, dq_flag
                      FROM dw.dwd_fact_payment
                     WHERE stat_date >= '2024-01-01' AND stat_date < '2025-01-01'
                    EXCEPT
                    SELECT * FROM tmp_dwd_full) b) = 0
            THEN 'Q1.4 PASS (双向 EXCEPT = 0)' ELSE 'Q1.4 FAIL' END AS result;
DROP TABLE tmp_dwd_full;

\echo '===== Q1.5  门店口径拦截 ====='
SELECT CASE WHEN (SELECT count(*) FROM dw.dim_store WHERE store_status='ACTIVE')
                 <> (SELECT count(*) FROM store)
            THEN 'Q1.5 PASS (ACTIVE=' || (SELECT count(*) FROM dw.dim_store WHERE store_status='ACTIVE')
                 || ' vs 裸表=' || (SELECT count(*) FROM store) || ')'
            ELSE 'Q1.5 FAIL' END AS result;

\echo '===== Q1.7  分区裁剪生效（正例：半开区间）====='
EXPLAIN (COSTS OFF) SELECT sum(amount) FROM dw.dwd_fact_payment
 WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01';

\echo '===== Q1.8  分区裁剪失效（反例：函数包裹分区键，防回归）====='
EXPLAIN (COSTS OFF) SELECT sum(amount) FROM dw.dwd_fact_payment
 WHERE EXTRACT(MONTH FROM stat_date) = 3;

\echo '===== Q1.9  水位线双轨：CV5 补录行必须归入正确月分区 ====='
SELECT CASE WHEN count(*) = 1 THEN 'Q1.9 PASS (补录行归入 2026-07)' ELSE 'Q1.9 FAIL' END AS result
  FROM dw.dwd_fact_payment
 WHERE payment_id = 900099999
   AND stat_date >= '2026-07-01' AND stat_date < '2026-08-01';

\echo '===== Q1.10 列存表形态 ====='
SELECT CASE WHEN count(*) = 2 THEN 'Q1.10 PASS' ELSE 'Q1.10 FAIL' END AS result,
       string_agg(relname || ' -> ' || array_to_string(reloptions, ','), ' | ') AS detail
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'dw' AND c.relname IN ('dwd_fact_payment','dwd_fact_rental')
  AND array_to_string(reloptions, ',') LIKE '%orientation=column%'
  AND array_to_string(reloptions, ',') LIKE '%compression=high%';

\echo '===== 补充：金额精度防溢出（RK3）====='
SELECT CASE WHEN sum(amount) > 999.99 THEN
            'precision PASS (DWD 总额 ' || sum(amount) || ' 远超源列 numeric(5,2) 上限)'
            ELSE 'precision FAIL' END AS result
  FROM dw.dwd_fact_payment;
