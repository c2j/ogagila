-- Phase 1 QA / Q1.6 — DQ 规则注入测试
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §9 Phase 1（Q1.6）
--
-- 每项注入一类缺陷，验证对应 DQ 规则命中且 severity 正确。
-- 判定：所有 INJ-* 行必须为 PASS。
--
-- 安全约定（务必遵守）：
--   1) 所有注入都必须在 BEGIN/ROLLBACK 内，或只作用于 dw 下的 scratch 表。
--   2) 绝不可对源表执行 DDL：ALTER TABLE ... TRUNCATE/DROP PARTITION 是 DDL，
--      **不受 ROLLBACK 保护**。早期版本用源表 payment 做索引失效注入，
--      结果真删掉了 2022-01 的 723 行业务数据（虽被 DQ 规则如实捕获，
--      但已构成数据事故）。GLOBAL_INDEX_INVALID 改用独立 scratch 表注入。
--   3) emit 用自治事务写入，故 ROLLBACK 后校验结论仍可见 —— 这是设计意图。

\set ON_ERROR_STOP off

DELETE FROM dw.dq_check_result WHERE run_id LIKE 'R_INJ%';

\echo '===== INJ-1  DWD 重复键 -> DWD_DUPLICATE_KEY (CRITICAL) ====='
BEGIN;
INSERT INTO dw.dwd_fact_payment(stat_date, payment_ts, payment_id, amount,
                                is_within_cutoff, dq_flag, run_id)
SELECT stat_date, payment_ts, payment_id, amount, is_within_cutoff, dq_flag, 'R_INJ'
  FROM dw.dwd_fact_payment WHERE payment_id = 900001001;
CALL dw.pkg_dq.run_all('R_INJ1', date '2024-01-01', date '2024-02-01');
SELECT CASE WHEN count(*) = 1 THEN 'INJ-1 PASS' ELSE 'INJ-1 FAIL' END AS result
  FROM dw.dq_check_result
 WHERE run_id = 'R_INJ1' AND rule_code = 'DWD_DUPLICATE_KEY' AND severity = 'CRITICAL';
ROLLBACK;

\echo '===== INJ-2  未截断 stat_date -> STAT_DATE_NOT_TRUNCATED (CRITICAL) ====='
BEGIN;
INSERT INTO dw.dwd_fact_payment(stat_date, payment_ts, payment_id, amount,
                                is_within_cutoff, dq_flag, run_id)
VALUES ('2024-01-15 13:45:00', '2024-01-15 13:45:00+00', 999999999, 1.00, true, false, 'R_INJ');
CALL dw.pkg_dq.run_all('R_INJ2', date '2024-01-01', date '2024-02-01');
SELECT CASE WHEN count(*) >= 1 THEN 'INJ-2 PASS' ELSE 'INJ-2 FAIL' END AS result
  FROM dw.dq_check_result
 WHERE run_id = 'R_INJ2' AND rule_code = 'STAT_DATE_NOT_TRUNCATED' AND severity = 'CRITICAL';
ROLLBACK;

\echo '===== INJ-3  源侧删除 -> SRC_ROW_DELETED (WARN) ====='
BEGIN;
DELETE FROM payment WHERE payment_id BETWEEN 900095001 AND 900095005;
CALL dw.pkg_dq.run_all('R_INJ3', date '2025-11-01', date '2025-12-01');
SELECT CASE WHEN count(*) = 1 THEN 'INJ-3 PASS' ELSE 'INJ-3 FAIL' END AS result
  FROM dw.dq_check_result
 WHERE run_id = 'R_INJ3' AND rule_code = 'SRC_ROW_DELETED' AND severity = 'WARN';
ROLLBACK;

\echo '===== INJ-4  兜底分区有行 -> PARTITION_OVERFLOW (CRITICAL) ====='
BEGIN;
INSERT INTO payment(customer_id, staff_id, rental_id, amount, payment_date)
  VALUES (1, 1, (SELECT min(rental_id) FROM rental), 9.99, '2099-01-01');
CALL dw.pkg_dq.run_all('R_INJ4', date '2099-01-01', date '2099-02-01');
SELECT CASE WHEN count(*) = 1 THEN 'INJ-4 PASS' ELSE 'INJ-4 FAIL' END AS result
  FROM dw.dq_check_result
 WHERE run_id = 'R_INJ4' AND rule_code = 'PARTITION_OVERFLOW' AND severity = 'CRITICAL';
ROLLBACK;

\echo '===== INJ-5  全局索引失效 -> GLOBAL_INDEX_INVALID (CRITICAL) ====='
\echo '--- 用独立 scratch 分区表注入，绝不触碰源表 ---'
DROP TABLE IF EXISTS dw.qa_scratch_part;
CREATE TABLE dw.qa_scratch_part (d date NOT NULL, k integer, v numeric(18,2))
PARTITION BY RANGE (d)
( PARTITION qa_scratch_p1 VALUES LESS THAN ('2024-02-01'),
  PARTITION qa_scratch_p2 VALUES LESS THAN ('2024-03-01') );
INSERT INTO dw.qa_scratch_part VALUES ('2024-01-15', 1, 1.00), ('2024-02-15', 2, 2.00);
CREATE INDEX idx_qa_scratch_global ON dw.qa_scratch_part (k) GLOBAL;
ALTER TABLE dw.qa_scratch_part TRUNCATE PARTITION qa_scratch_p1;
CALL dw.pkg_dq.run_all('R_INJ5', date '2024-01-01', date '2024-02-01');
SELECT CASE WHEN count(*) = 1 THEN 'INJ-5 PASS' ELSE 'INJ-5 FAIL' END AS result
  FROM dw.dq_check_result
 WHERE run_id = 'R_INJ5' AND rule_code = 'GLOBAL_INDEX_INVALID' AND severity = 'CRITICAL';
DROP TABLE dw.qa_scratch_part;

\echo '===== 清理 ====='
DELETE FROM dw.dq_check_result WHERE run_id LIKE 'R_INJ%';
SELECT CASE WHEN count(*) = 0 THEN 'cleanup PASS' ELSE 'cleanup FAIL' END AS result
  FROM dw.dq_check_result WHERE run_id LIKE 'R_INJ%';
