-- Phase 1 QA / Q1.11 — 水位线双轨增量验收
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §6.2 / §6.3 / §6.4
--
-- 前置：已加载 t1-deterministic.sql（会重置水位线）、已建 DIM。
-- 判定：所有 Q1.11-* 行必须为 PASS。
--
-- 本脚本证明四件事，其中 C2 刻意验证的是"设计上会漏、由对账兜住"：
--   A)  首次增量（水位线为 NULL）等价于全量，且逐行一致；
--   B)  稳态增量只重建受影响月份 —— 注意由于 lookback_days 回溯窗口的存在，
--       近月每次都会被重扫，这是**设计意图**（回补迟到数据），不是缺陷；
--   C1) 回溯窗**内**的补录行被 TS 轨捕获；
--   C2) 回溯窗**外**且 id 低于水位线的补录行**双轨全漏**（ID 轨前提被破坏），
--       必须由月度全量对账 RECON_DWD_VS_BASE 兜住 —— 这正是 §6.3 存在的理由。

\set ON_ERROR_STOP off

\echo '===== 准备：重置水位线 + 清空 DWD payment ====='
UPDATE dw.etl_watermark SET wm_id_value = NULL, wm_ts_value = NULL, last_run_id = NULL
 WHERE source_name = 'payment';
DELETE FROM dw.dwd_fact_payment;

\echo '===== Q1.11-A  首次增量 == 全量（逐行一致）====='
DECLARE
    v_rows integer; v_months integer; v_status varchar2(16);
    v_inc_cnt bigint; v_inc_sum numeric; v_full_cnt bigint; v_full_sum numeric;
    v_diff bigint;
BEGIN
    dw.pkg_dwd.build_payment_incremental('R_Q111A', v_rows, v_months);
    SELECT count(*), COALESCE(sum(amount),0) INTO v_inc_cnt, v_inc_sum FROM dw.dwd_fact_payment;

    CREATE TEMP TABLE tmp_inc AS
    SELECT stat_date, payment_id, store_id, store_status, category_id, amount,
           is_within_cutoff, dq_flag FROM dw.dwd_fact_payment;

    dw.pkg_dwd.build_dwd_fact_payment(date '2022-01-01', date '2027-01-01',
                                      'R_Q111A_FULL', v_rows, v_status);
    SELECT count(*), COALESCE(sum(amount),0) INTO v_full_cnt, v_full_sum FROM dw.dwd_fact_payment;

    SELECT (SELECT count(*) FROM (SELECT * FROM tmp_inc EXCEPT
              SELECT stat_date, payment_id, store_id, store_status, category_id, amount,
                     is_within_cutoff, dq_flag FROM dw.dwd_fact_payment) a)
         + (SELECT count(*) FROM (SELECT stat_date, payment_id, store_id, store_status,
                     category_id, amount, is_within_cutoff, dq_flag FROM dw.dwd_fact_payment
              EXCEPT SELECT * FROM tmp_inc) b) INTO v_diff;

    IF v_inc_cnt = v_full_cnt AND v_inc_sum = v_full_sum AND v_diff = 0 THEN
        RAISE NOTICE 'Q1.11-A PASS (增量 %/% == 全量 %/%，双向 EXCEPT=0，覆盖 % 个月)',
            v_inc_cnt, v_inc_sum, v_full_cnt, v_full_sum, v_months;
    ELSE
        RAISE NOTICE 'Q1.11-A FAIL (inc=%/% full=%/% diff=%)',
            v_inc_cnt, v_inc_sum, v_full_cnt, v_full_sum, v_diff;
    END IF;
    DROP TABLE tmp_inc;
END;
/

\echo '===== Q1.11-B  稳态增量只重建"回溯窗覆盖的少数月份" ====='
DECLARE
    v_rows integer; v_months integer;
BEGIN
    dw.pkg_dwd.build_payment_incremental('R_Q111B1', v_rows, v_months);
    IF v_months <= 2 THEN
        RAISE NOTICE 'Q1.11-B1 PASS (无新数据时仅回溯窗覆盖的 % 个月被重扫，<=2)', v_months;
    ELSE
        RAISE NOTICE 'Q1.11-B1 FAIL (重建了 % 个月，远超回溯窗范围)', v_months;
    END IF;
END;
/

\echo '--- 插入 1 笔新交易（近 3 天内）后仍应只重建少数月份 ---'
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, staff_id)
  VALUES (900097001, now() - interval '3 days', 900000002, 900000001, 900000001);
INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date)
  VALUES (900097001, 900000001, 900000001, 900097001, 12.34, now() - interval '3 days');

DECLARE
    v_rows integer; v_months integer;
BEGIN
    dw.pkg_dwd.build_payment_incremental('R_Q111B2', v_rows, v_months);
    IF v_months BETWEEN 1 AND 2 THEN
        RAISE NOTICE 'Q1.11-B2 PASS (重建 % 个月，% 行)', v_months, v_rows;
    ELSE
        RAISE NOTICE 'Q1.11-B2 FAIL (重建了 % 个月)', v_months;
    END IF;
END;
/
SELECT CASE WHEN count(*) = 1 THEN 'Q1.11-C1 PASS (回溯窗内的新行被 TS 轨捕获)'
            ELSE 'Q1.11-C1 FAIL' END AS result
  FROM dw.dwd_fact_payment WHERE payment_id = 900097001;

\echo '===== Q1.11-C2  回溯窗外 + id 低于水位线 -> 双轨全漏，由对账兜住 ====='
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, staff_id)
  VALUES (900097002, '2024-05-10 09:00:00+00', 900000003, 900000001, 900000001);
INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date)
  VALUES (900097002, 900000001, 900000001, 900097002, 56.78, '2024-05-10 09:00:00+00');

DECLARE
    v_rows integer; v_months integer;
BEGIN
    dw.pkg_dwd.build_payment_incremental('R_Q111C2', v_rows, v_months);
    RAISE NOTICE 'Q1.11-C2 增量重建 % 个月（预期不含 2024-05）', v_months;
END;
/
SELECT CASE WHEN count(*) = 0
            THEN 'Q1.11-C2a PASS (如设计所述：增量确实漏掉了该行)'
            ELSE 'Q1.11-C2a UNEXPECTED (增量意外捕获了该行)' END AS result
  FROM dw.dwd_fact_payment WHERE payment_id = 900097002;

\echo '--- 对账必须发现这个缺口（§6.3 月度全量对账的价值证明）---'
DELETE FROM dw.dq_check_result WHERE run_id = 'R_Q111C2_DQ';
CALL dw.pkg_dq.run_all('R_Q111C2_DQ', date '2024-05-01', date '2024-06-01');
SELECT CASE WHEN count(*) = 1
            THEN 'Q1.11-C2b PASS (RECON_DWD_VS_BASE 捕获缺口)'
            ELSE 'Q1.11-C2b FAIL (对账未发现缺口)' END AS result
  FROM dw.dq_check_result
 WHERE run_id = 'R_Q111C2_DQ' AND rule_code = 'RECON_DWD_VS_BASE' AND severity = 'CRITICAL';

\echo '--- 兜底动作：对受影响月份做全量重建后缺口应闭合 ---'
DECLARE v_rows integer; v_status varchar2(16);
BEGIN
    dw.pkg_dwd.build_dwd_fact_payment(date '2024-05-01', date '2024-06-01',
                                      'R_Q111C2_FIX', v_rows, v_status);
END;
/
SELECT CASE WHEN count(*) = 1 THEN 'Q1.11-C2c PASS (全量重建后该行已入 DWD)'
            ELSE 'Q1.11-C2c FAIL' END AS result
  FROM dw.dwd_fact_payment WHERE payment_id = 900097002;

\echo '===== Q1.11-D  最终逐月对账必须为 0 ====='
SELECT CASE WHEN count(*) = 0 THEN 'Q1.11-D PASS (逐月对账 0 差异)'
            ELSE 'Q1.11-D FAIL (' || count(*) || ' 个月不一致)' END AS result
  FROM (SELECT COALESCE(d.m, s.m) m
          FROM (SELECT date_trunc('month', stat_date) m, count(*) c, sum(amount) a
                  FROM dw.dwd_fact_payment GROUP BY 1) d
          FULL JOIN (SELECT date_trunc('month', payment_date) m, count(*) c, sum(amount) a
                       FROM public.payment GROUP BY 1) s ON s.m = d.m
         WHERE COALESCE(d.c,-1) <> COALESCE(s.c,-1)
            OR COALESCE(d.a,-1) <> COALESCE(s.a,-1)) t;

\echo '===== 清理 ====='
DELETE FROM payment WHERE payment_id IN (900097001, 900097002);
DELETE FROM rental  WHERE rental_id  IN (900097001, 900097002);
DELETE FROM dw.dq_check_result WHERE run_id LIKE 'R_Q111%';
DECLARE v_rows integer; v_status varchar2(16);
BEGIN
    dw.pkg_dwd.build_dwd_fact_payment(date '2024-05-01', date '2024-06-01', 'R_CLEAN', v_rows, v_status);
    dw.pkg_dwd.build_dwd_fact_payment(date '2026-08-01', date '2026-10-01', 'R_CLEAN', v_rows, v_status);
END;
/
SELECT CASE WHEN count(*) = 0 THEN 'cleanup PASS' ELSE 'cleanup FAIL' END AS result
  FROM dw.dwd_fact_payment WHERE payment_id IN (900097001, 900097002);
