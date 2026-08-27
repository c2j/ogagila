-- Phase 2 QA — PKG_ORCH 双模式 + worker 契约（Q2.9 ~ Q2.13）
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §5.3 / §5.3.1 / §9 Phase 2
--
-- 前置：已加载夹具、已建 DIM 与 DWD。
-- 判定：所有 Q2.* 行必须为 PASS。
--
-- 最重要的是 Q2.13 **模式等价性**：QUEUE 模式的裸 SQL 与 DIRECT 模式的静态 SQL
-- 是两处定义，本用例是防止二者漂移的唯一保障。改动任一处都必须重跑本用例。

\set ON_ERROR_STOP off

\echo '===== 准备 ====='
DELETE FROM dw.etl_task_queue WHERE run_id LIKE 'R_ORCH%';

\echo '===== Q2.9  QUEUE 模式投递的是裸 SQL（K2 前提）====='
CALL dw.pkg_orch.run_monthly(date '2025-03-01', 'R_ORCH_Q', 'QUEUE');
SELECT CASE WHEN count(*) = 2
            THEN 'Q2.9 PASS (重型步骤投递为裸 DELETE/INSERT，非 CALL)'
            ELSE 'Q2.9 FAIL' END AS result
  FROM dw.etl_task_queue
 WHERE run_id = 'R_ORCH_Q'
   AND step_name IN ('monthly_payment', 'monthly_rental')
   AND sql_text LIKE 'DELETE FROM dw.dwd_fact_%'
   AND sql_text NOT LIKE '%CALL %';

\echo '===== Q2.10 依赖链严格串行（K7 前提）====='
SELECT CASE WHEN count(*) = 3 THEN 'Q2.10 PASS (seq 3->4->5 串行链)' ELSE 'Q2.10 FAIL' END AS result
  FROM dw.etl_task_queue
 WHERE run_id = 'R_ORCH_Q'
   AND ((seq_no = 3 AND depends_on IS NULL)
     OR (seq_no = 4 AND depends_on = 3)
     OR (seq_no = 5 AND depends_on = 4));

\echo '===== Q2.11 入队幂等（K5）====='
CALL dw.pkg_orch.run_monthly(date '2025-03-01', 'R_ORCH_Q', 'QUEUE');
SELECT CASE WHEN count(*) = 3 THEN 'Q2.11 PASS (重复编排未产生重复任务)'
            ELSE 'Q2.11 FAIL (' || count(*) || ' tasks)' END AS result
  FROM dw.etl_task_queue WHERE run_id = 'R_ORCH_Q';

\echo '===== Q2.12 参数校验：非法 mode 必须拒绝 ====='
CALL dw.pkg_orch.run_monthly(date '2025-03-01', 'R_ORCH_BAD', 'TURBO');
SELECT CASE WHEN count(*) = 0 THEN 'Q2.12 PASS (非法 mode 被拒绝，未入队)'
            ELSE 'Q2.12 FAIL' END AS result
  FROM dw.etl_task_queue WHERE run_id = 'R_ORCH_BAD';

\echo '===== Q2.13 模式等价性（防 SQL 漂移，最关键）====='
DECLARE
    v_rows integer; v_status varchar2(16); v_diff bigint;
BEGIN
    -- DIRECT 模式产出作为基线
    dw.pkg_dwd.build_dwd_fact_payment(date '2025-03-01', date '2025-04-01',
                                      'R_EQ_DIRECT', v_rows, v_status);
    CREATE TEMP TABLE tmp_direct AS
    SELECT stat_date, payment_id, store_id, store_status, category_id, category_name,
           store_city, store_country, amount, is_within_cutoff, multi_category, dq_flag
      FROM dw.dwd_fact_payment
     WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01';

    -- QUEUE 模式的裸 SQL 直接执行（等同 worker 的顶层提交）
    EXECUTE IMMEDIATE dw.pkg_dwd.gen_payment_sql(date '2025-03-01', date '2025-04-01',
                                                 'R_EQ_QUEUE');

    SELECT (SELECT count(*) FROM (SELECT * FROM tmp_direct EXCEPT
              SELECT stat_date, payment_id, store_id, store_status, category_id, category_name,
                     store_city, store_country, amount, is_within_cutoff, multi_category, dq_flag
                FROM dw.dwd_fact_payment
               WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01') a)
         + (SELECT count(*) FROM (SELECT stat_date, payment_id, store_id, store_status,
                     category_id, category_name, store_city, store_country, amount,
                     is_within_cutoff, multi_category, dq_flag
                FROM dw.dwd_fact_payment
               WHERE stat_date >= '2025-03-01' AND stat_date < '2025-04-01'
              EXCEPT SELECT * FROM tmp_direct) b) INTO v_diff;

    IF v_diff = 0 THEN
        RAISE NOTICE 'Q2.13 PASS (DIRECT 与 QUEUE 产出双向 EXCEPT = 0，无漂移)';
    ELSE
        RAISE NOTICE 'Q2.13 FAIL (差异 % 行 —— 两处 SQL 已漂移，必须同步)', v_diff;
    END IF;
    DROP TABLE tmp_direct;
END;
/

\echo '===== Q2.13b rental 侧同样等价 ====='
DECLARE
    v_rows integer; v_status varchar2(16); v_diff bigint;
BEGIN
    dw.pkg_dwd.build_dwd_fact_rental(date '2022-05-01', date '2022-06-01',
                                     'R_EQ_DIRECT', v_rows, v_status);
    CREATE TEMP TABLE tmp_direct_r AS
    SELECT stat_date, rental_id, store_id, store_status, category_id,
           is_returned, is_overdue, overdue_days, is_within_cutoff, dq_flag
      FROM dw.dwd_fact_rental
     WHERE stat_date >= '2022-05-01' AND stat_date < '2022-06-01';

    EXECUTE IMMEDIATE dw.pkg_dwd.gen_rental_sql(date '2022-05-01', date '2022-06-01',
                                                'R_EQ_QUEUE');

    SELECT (SELECT count(*) FROM (SELECT * FROM tmp_direct_r EXCEPT
              SELECT stat_date, rental_id, store_id, store_status, category_id,
                     is_returned, is_overdue, overdue_days, is_within_cutoff, dq_flag
                FROM dw.dwd_fact_rental
               WHERE stat_date >= '2022-05-01' AND stat_date < '2022-06-01') a)
         + (SELECT count(*) FROM (SELECT stat_date, rental_id, store_id, store_status,
                     category_id, is_returned, is_overdue, overdue_days,
                     is_within_cutoff, dq_flag
                FROM dw.dwd_fact_rental
               WHERE stat_date >= '2022-05-01' AND stat_date < '2022-06-01'
              EXCEPT SELECT * FROM tmp_direct_r) b) INTO v_diff;

    IF v_diff = 0 THEN
        RAISE NOTICE 'Q2.13b PASS (rental 双模式无漂移)';
    ELSE
        RAISE NOTICE 'Q2.13b FAIL (差异 % 行)', v_diff;
    END IF;
    DROP TABLE tmp_direct_r;
END;
/

\echo '===== 清理 ====='
DELETE FROM dw.etl_task_queue WHERE run_id LIKE 'R_ORCH%';
DELETE FROM dw.etl_run_log    WHERE run_id LIKE 'R_ORCH%' OR run_id LIKE 'R_EQ_%';
SELECT CASE WHEN count(*) = 0 THEN 'cleanup PASS' ELSE 'cleanup FAIL' END AS result
  FROM dw.etl_task_queue WHERE run_id LIKE 'R_ORCH%';
