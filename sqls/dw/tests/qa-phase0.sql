-- Phase 0 QA — 可执行验收脚本 Q0.1 ~ Q0.6
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §9 Phase 0
--
-- 用法：docker exec pagila gsql-pagila -f /tmp/qa-phase0.sql
-- 判定：所有输出行必须为 PASS。Q0.5 的并发用例需单独跑（见文件末尾说明）。

\set ON_ERROR_STOP off

\echo '===== Q0.1  MAXVALUE 兜底分区生效 ====='
BEGIN;
INSERT INTO payment(customer_id, staff_id, rental_id, amount, payment_date)
  VALUES (1, 1, (SELECT min(rental_id) FROM rental), 9.99, '2099-01-01');
SELECT CASE WHEN count(*) = 1 THEN 'Q0.1 PASS' ELSE 'Q0.1 FAIL' END AS result
  FROM payment WHERE payment_date >= '2099-01-01';
ROLLBACK;

\echo '===== Q0.2a 4 个 FK 索引存在 ====='
SELECT CASE WHEN count(*) = 4 THEN 'Q0.2a PASS'
            ELSE 'Q0.2a FAIL (' || count(*) || '/4)' END AS result
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN ('idx_fk_payment_rental_id', 'idx_fk_rental_customer_id',
                    'idx_fk_rental_staff_id', 'idx_fk_film_category_category_id');

\echo '===== Q0.2b 索引可被优化器使用（人工核对计划中出现索引名）====='
\echo '--- expect: Partitioned Bitmap Index Scan on idx_fk_payment_rental_id ---'
EXPLAIN (COSTS OFF) SELECT * FROM payment WHERE rental_id = 100;
\echo '--- expect: Bitmap Index Scan on idx_fk_rental_customer_id ---'
EXPLAIN (COSTS OFF) SELECT * FROM rental WHERE customer_id = 100;
\echo '--- expect: Bitmap Index Scan on idx_fk_film_category_category_id ---'
EXPLAIN (COSTS OFF) SELECT * FROM film_category WHERE category_id = 5;
-- rental.staff_id 在当前演示数据上只有 2 个不同值 / 16044 行（选择性 ~50%），
-- 优化器选 Seq Scan 是正确决策，不代表索引不可用。故用 Plan Hint 强制走索引
-- 以验证"可用性"，与"优化器是否选它"解耦（规模化后 staff 上千，自然会选索引）。
\echo '--- expect: Index Scan using idx_fk_rental_staff_id (hint 强制) ---'
EXPLAIN (COSTS OFF) SELECT /*+ indexscan(rental idx_fk_rental_staff_id) */ *
  FROM rental WHERE staff_id = 1;

\echo '===== Q0.3  分区哨兵幂等 ====='
CALL dw.pkg_etl_core.ensure_partitions('payment', 3);
SELECT count(*) AS parts_run1 INTO TEMP TABLE tmp_q03
  FROM pg_partition WHERE parentid = 'public.payment'::regclass AND parttype = 'p';
CALL dw.pkg_etl_core.ensure_partitions('payment', 3);
SELECT CASE WHEN (SELECT parts_run1 FROM tmp_q03) = count(*) THEN 'Q0.3 PASS'
            ELSE 'Q0.3 FAIL' END AS result
  FROM pg_partition WHERE parentid = 'public.payment'::regclass AND parttype = 'p';
DROP TABLE tmp_q03;

\echo '--- Q0.3 补充：pmax 仍兜住远期行 + 当月行正确路由 ---'
BEGIN;
INSERT INTO payment(customer_id, staff_id, rental_id, amount, payment_date)
  VALUES (1, 1, (SELECT min(rental_id) FROM rental), 9.99, '2099-01-01');
SELECT CASE WHEN count(*) = 1 THEN 'Q0.3-pmax PASS' ELSE 'Q0.3-pmax FAIL' END AS result
  FROM payment PARTITION (payment_pmax);
ROLLBACK;

\echo '===== Q0.4  etl_task_queue 入队去重（K5）====='
DELETE FROM dw.etl_task_queue WHERE run_id = 'R_QA_DEDUP';
INSERT INTO dw.etl_task_queue(run_id, step_name, seq_no, sql_text)
  VALUES ('R_QA_DEDUP', 's1', 1, 'SELECT 1');
\echo '--- 下一条应报 duplicate key（etl_task_queue_uk）---'
INSERT INTO dw.etl_task_queue(run_id, step_name, seq_no, sql_text)
  VALUES ('R_QA_DEDUP', 's1', 1, 'SELECT 1');
INSERT INTO dw.etl_task_queue(run_id, step_name, seq_no, sql_text)
  VALUES ('R_QA_DEDUP', 's1', 1, 'SELECT 999')
  ON DUPLICATE KEY UPDATE NOTHING;
SELECT CASE WHEN count(*) = 1 AND max(sql_text) = 'SELECT 1' THEN 'Q0.4 PASS'
            ELSE 'Q0.4 FAIL' END AS result
  FROM dw.etl_task_queue WHERE run_id = 'R_QA_DEDUP';
DELETE FROM dw.etl_task_queue WHERE run_id = 'R_QA_DEDUP';

\echo '===== Q0.6  自治事务审计留痕 ====='
-- 验证 §5.3 的审计模式：主事务因 RAISE_APPLICATION_ERROR 回滚后，
-- 由自治事务写入的 etl_run_log 记录仍必须存在。
CREATE OR REPLACE PROCEDURE dw.qa_fail_demo(p_run_id varchar2) IS
BEGIN
    dw.pkg_etl_core.log_start(p_run_id, 'qa_step');
    INSERT INTO dw.dq_check_result(run_id, rule_code, severity)
      VALUES (p_run_id, 'QA_SHOULD_ROLLBACK', 'INFO');
    RAISE_APPLICATION_ERROR(-20099, 'intentional failure');
EXCEPTION WHEN OTHERS THEN
    dw.pkg_etl_core.log_end(p_run_id, 'qa_step', 'FAILED', 0, SQLSTATE, SQLERRM);
    RAISE;
END;
/
DELETE FROM dw.etl_run_log     WHERE run_id = 'R_QA_AUTO';
DELETE FROM dw.dq_check_result WHERE run_id = 'R_QA_AUTO';
\echo '--- 下一条应报 ORA-20099（预期失败）---'
CALL dw.qa_fail_demo('R_QA_AUTO');
SELECT CASE WHEN (SELECT count(*) FROM dw.etl_run_log
                   WHERE run_id = 'R_QA_AUTO' AND status = 'FAILED') = 1
             AND (SELECT count(*) FROM dw.dq_check_result
                   WHERE run_id = 'R_QA_AUTO') = 0
            THEN 'Q0.6 PASS (日志留存 + 业务写入已回滚)'
            ELSE 'Q0.6 FAIL' END AS result;
DROP PROCEDURE dw.qa_fail_demo;
DELETE FROM dw.etl_run_log WHERE run_id = 'R_QA_AUTO';

\echo '===== Q0.5 说明 ====='
\echo 'Q0.5（并发原子领取）需两个会话并发执行，见 sqls/dw/tests/qa-phase0-concurrent.sh'
