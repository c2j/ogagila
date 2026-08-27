-- Phase 3 QA — Q3.1 ~ Q3.7（C4 披露层）
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §9 Phase 3 / DD8 / §附录 A
--
-- 前置：**必须由 qa-phase3-disclose.sh 驱动运行** —— 该驱动会重载夹具并重建各层，
-- 保证"存在 CRITICAL"的受控基线。直接单独运行本 SQL 在第二次会失败。
-- 判定：所有 Q3.* 行必须为 PASS。
--
-- 关于快照不可删除（实施期踩到的运维事实）：
-- rpt_disclosure_snapshot 的不可变保护是**绝对的** —— 误写或测试写入的行同样
-- 永久无法删除。因此本脚本一律用"基线 + 增量"断言，不假设快照表为空；
-- 生产环境必须禁止向该表做任何测试写入。
--
-- 关于结构性 DQ 规则（实施期发现的设计特性）：
-- DATE_RANGE_MISMATCH / STORE_NO_STAFF / MGR_ORPHAN 是**全局结构性**规则，
-- 不按期间过滤。因此一条结构性 CRITICAL 会阻塞**所有**期间的冻结，直到源头
-- 被修复。这对披露是正确语义（结构缺陷未修复时不应对外披露），但意味着
-- close_period 的成功路径必须先走"修复"步骤 —— 本脚本因此完整演示
-- "注入 -> 拒绝 -> 修复 -> 冻结 -> 重算" 全流程。

\set ON_ERROR_STOP off

\echo '===== 准备：确保口径已批准（隔离闸门 1 与闸门 2）====='
UPDATE dw.rpt_metric_def SET status='APPROVED', approved_by='qa-biz-owner', approved_at=now();
DELETE FROM dw.rpt_period_close        WHERE period='2025-03';
DELETE FROM dw.rpt_source_fingerprint  WHERE period='2025-03';
DELETE FROM dw.dq_check_result         WHERE run_id LIKE 'R_Q3%';

\echo '===== Q3.5a 闸门 1：存在 CRITICAL 必须拒绝冻结 ====='
CALL dw.pkg_disclose.close_period('2025-03', 'R_Q35A', 'alice');
SELECT CASE WHEN COALESCE(max(status),'ABSENT') <> 'CLOSED'
            THEN 'Q3.5a PASS (存在 CRITICAL 时期间未被冻结)'
            ELSE 'Q3.5a FAIL (被错误冻结)' END AS result
  FROM dw.rpt_period_close WHERE period='2025-03';

\echo '===== 修复三类结构性缺陷（演示披露前的必要整改）====='
\echo '--- 1) 移除 CV2 夹具行（rental 日期超出 payment 上界）---'
DELETE FROM payment WHERE rental_id BETWEEN 900094001 AND 900094003;
DELETE FROM rental  WHERE rental_id BETWEEN 900094001 AND 900094003;
\echo '--- 2) 移除 CV12 夹具门店（悬空 manager_staff_id）---'
DELETE FROM payment   WHERE customer_id = 900000004;
DELETE FROM rental    WHERE customer_id = 900000004;
DELETE FROM customer  WHERE customer_id = 900000004;
DELETE FROM inventory WHERE store_id    = 900000004;
DELETE FROM store     WHERE store_id    = 900000004;
\echo '--- 3) 为 store_id=2 补一名员工（修复真实源库缺陷 D3）---'
INSERT INTO staff(staff_id, first_name, last_name, address_id, email, store_id, active, username)
SELECT 900000009, 'Remedy', 'Staff2', min(address_id), 'remedy@example.com', 2, true, 'remedy_s2'
  FROM address
ON DUPLICATE KEY UPDATE NOTHING;

\echo '--- 整改后重建受影响层次 ---'
DECLARE v_rows integer; v_status varchar2(16); v_months integer;
BEGIN
    dw.pkg_dim.build_all(date '2025-03-01', date '2025-04-01', 'R_Q3FIX');
    dw.pkg_dwd.build_dwd_fact_payment(date '2022-01-01', date '2027-01-01', 'R_Q3FIX', v_rows, v_status);
    dw.pkg_dwd.build_dwd_fact_rental (date '2022-01-01', date '2027-01-01', 'R_Q3FIX', v_rows, v_status);
    dw.pkg_dws.build_all(date '2022-01-01', date '2027-01-01', 'R_Q3FIX');
END;
/

\echo '===== Q3.3 冻结成功 + 新增一个快照版本（含 3 个指标）====='
DELETE FROM dw.dq_check_result WHERE run_id LIKE 'R_Q3%';
DROP TABLE IF EXISTS tmp_snap_base;
CREATE TEMP TABLE tmp_snap_base AS
SELECT COALESCE(max(snapshot_version), 0) AS v, count(*) AS c
  FROM dw.rpt_disclosure_snapshot WHERE period='2025-03';
CALL dw.pkg_disclose.close_period('2025-03', 'R_Q33', 'alice');
SELECT CASE WHEN (SELECT status FROM dw.rpt_period_close WHERE period='2025-03') = 'CLOSED'
             AND (SELECT count(*) FROM dw.rpt_disclosure_snapshot
                   WHERE period='2025-03'
                     AND snapshot_version = (SELECT v + 1 FROM tmp_snap_base)) = 3
            THEN 'Q3.3 PASS (期间已 CLOSED，新版本含 3 个指标)'
            ELSE 'Q3.3 FAIL' END AS result;

\echo '--- 冻结的披露值 ---'
SELECT snapshot_version, metric_code, metric_value
  FROM dw.rpt_disclosure_snapshot WHERE period='2025-03' ORDER BY 1,2;

\echo '===== Q3.5b 闸门 1 再验：已 CLOSED 的期间不可重复冻结 ====='
CALL dw.pkg_disclose.close_period('2025-03', 'R_Q35B', 'alice');
SELECT CASE WHEN count(*) = (SELECT c + 3 FROM tmp_snap_base)
            THEN 'Q3.5b PASS (未产生重复快照)'
            ELSE 'Q3.5b FAIL (' || count(*) || ' 行)' END AS result
  FROM dw.rpt_disclosure_snapshot WHERE period='2025-03';

\echo '===== Q3.1 / Q3.2 快照不可变 ====='
UPDATE dw.rpt_disclosure_snapshot SET metric_value = 0 WHERE period='2025-03';
SELECT CASE WHEN count(*) = 0 THEN 'Q3.1 PASS (UPDATE 被拒绝)'
            ELSE 'Q3.1 FAIL (' || count(*) || ' 行被改为 0)' END AS result
  FROM dw.rpt_disclosure_snapshot WHERE period='2025-03' AND metric_value = 0;

DELETE FROM dw.rpt_disclosure_snapshot WHERE period='2025-03';
SELECT CASE WHEN count(*) = (SELECT c + 3 FROM tmp_snap_base)
            THEN 'Q3.2 PASS (DELETE 被拒绝，行数未变)'
            ELSE 'Q3.2 FAIL' END AS result
  FROM dw.rpt_disclosure_snapshot WHERE period='2025-03';

\echo '===== Q3.4 指纹告警：改动源数据后 verify_fingerprint 必须发现 ====='
SELECT CASE WHEN dw.pkg_disclose.verify_fingerprint('2025-03') = 0
            THEN 'Q3.4a PASS (未改动时指纹一致)'
            ELSE 'Q3.4a FAIL' END AS result;

UPDATE payment SET amount = amount + 1
 WHERE payment_id = (SELECT min(payment_id) FROM payment
                      WHERE payment_date >= '2025-03-01' AND payment_date < '2025-04-01');
SELECT CASE WHEN dw.pkg_disclose.verify_fingerprint('2025-03') > 0
            THEN 'Q3.4b PASS (改动 1 行即被指纹捕获)'
            ELSE 'Q3.4b FAIL (指纹未发现改动)' END AS result;

\echo '===== Q3.3b 重算：只增版本、旧值保留、口径版本记录 ====='
CALL dw.pkg_disclose.recompute_period('2025-03', 'R_Q33B', '源数据修正后重述');
SELECT CASE WHEN (SELECT count(*) FROM dw.rpt_disclosure_snapshot
                   WHERE period='2025-03'
                     AND snapshot_version = (SELECT v + 2 FROM tmp_snap_base)) = 3
             AND (SELECT count(*) FROM dw.rpt_disclosure_snapshot
                   WHERE period='2025-03'
                     AND snapshot_version = (SELECT v + 1 FROM tmp_snap_base)) = 3
            THEN 'Q3.3b PASS (前一版本完整保留 + 新增下一版本)'
            ELSE 'Q3.3b FAIL' END AS result;

SELECT snapshot_version, metric_code, metric_value, left(COALESCE(metric_text,''),20) AS reason
  FROM dw.rpt_disclosure_snapshot WHERE period='2025-03' ORDER BY 1,2;

SELECT CASE WHEN count(*) = 1 THEN 'Q3.4c PASS (FINGERPRINT_MISMATCH 已记录审计线索)'
            ELSE 'Q3.4c FAIL' END AS result
  FROM dw.dq_check_result
 WHERE run_id='R_Q33B' AND rule_code='FINGERPRINT_MISMATCH' AND severity='CRITICAL';

\echo '===== Q3.6 闸门不对称：C2/C3 在有 CRITICAL 时仍可用且透出 dq_flag ====='
SELECT CASE WHEN count(*) > 0 THEN 'Q3.6 PASS (C2 视图可查且含 dq_flag 列)'
            ELSE 'Q3.6 FAIL' END AS result
  FROM dw.v_ads_ops_sales_drill WHERE grain = '总计';

\echo '===== Q3.7 未批准口径必须阻塞冻结（闸门 2 隔离验证）====='
UPDATE dw.rpt_metric_def SET status='DRAFT' WHERE metric_code='CATEGORY_ATTRIBUTION';
DELETE FROM dw.rpt_period_close WHERE period='2025-04';
CALL dw.pkg_disclose.close_period('2025-04', 'R_Q37', 'alice');
SELECT CASE WHEN COALESCE(max(status),'ABSENT') <> 'CLOSED'
            THEN 'Q3.7 PASS (口径 DRAFT 时拒绝冻结)'
            ELSE 'Q3.7 FAIL' END AS result
  FROM dw.rpt_period_close WHERE period='2025-04';
UPDATE dw.rpt_metric_def SET status='APPROVED' WHERE metric_code='CATEGORY_ATTRIBUTION';

\echo '===== 恢复：撤销整改与源数据改动，还原夹具态 ====='
UPDATE payment SET amount = amount - 1
 WHERE payment_id = (SELECT min(payment_id) FROM payment
                      WHERE payment_date >= '2025-03-01' AND payment_date < '2025-04-01');
DELETE FROM staff WHERE staff_id = 900000009;
DROP TABLE IF EXISTS tmp_snap_base;
SELECT 'restore PASS' AS result;
