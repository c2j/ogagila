-- Phase 3 — PKG_DISCLOSE：披露层冻结与重算
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §4.3 / DD8 / §附录 A 闸门语义
-- 口径依据：sqls/dw/docs/metric-definitions.md §1 §5 §11
--
-- 闸门不对称是分层的核心价值（附录 A）：
--   C1/C2/C3 见 CRITICAL 不阻塞，仅透出 dq_flag -> 运营可用带瑕疵数据决策
--   C4 披露    0 CRITICAL 才允许冻结 -> 代码级硬拒绝，不留 p_force 后门
--
-- 除 DQ 闸门外还有第二道闸门：口径定义必须已 APPROVED。
-- 未签字的口径（B1~B5 当前为 DRAFT）不得对外披露 —— 这是 RK1（"500 家门店"
-- 进入公开文件构成实质性错误陈述）的最后一道防线。

\set ON_ERROR_STOP on
SET check_function_bodies = false;

CREATE OR REPLACE PACKAGE dw.pkg_disclose IS
    PROCEDURE take_fingerprint(p_period varchar2, p_run_id varchar2);
    PROCEDURE close_period(p_period varchar2, p_run_id varchar2, p_closed_by varchar2);
    PROCEDURE recompute_period(p_period varchar2, p_run_id varchar2, p_reason text);
    FUNCTION  verify_fingerprint(p_period varchar2) RETURN integer;
END pkg_disclose;
/

CREATE OR REPLACE PACKAGE BODY dw.pkg_disclose IS

    -- 采集输入指纹。md5 汇总用 string_agg(... ORDER BY pk) 保证确定性 ——
    -- 不排序则同一数据集在不同扫描顺序下会得到不同 checksum，指纹失去意义。
    PROCEDURE take_fingerprint(p_period varchar2, p_run_id varchar2) IS
        v_from date := to_date(p_period || '-01', 'YYYY-MM-DD');
        v_to   date;
    BEGIN
        v_to := (v_from + interval '1 month')::date;
        dw.pkg_etl_core.log_start(p_run_id, 'take_fingerprint');

        INSERT INTO dw.rpt_source_fingerprint(
            period, table_name, row_count, sum_amount, min_pk, max_pk, checksum, run_id)
        SELECT p_period, 'public.payment', count(*), sum(amount),
               min(payment_id), max(payment_id),
               md5(COALESCE(string_agg(payment_id || ':' || amount, ',' ORDER BY payment_id), '')),
               p_run_id
          FROM public.payment
         WHERE payment_date >= v_from AND payment_date < v_to;

        INSERT INTO dw.rpt_source_fingerprint(
            period, table_name, row_count, sum_amount, min_pk, max_pk, checksum, run_id)
        SELECT p_period, 'public.rental', count(*), NULL,
               min(rental_id), max(rental_id),
               md5(COALESCE(string_agg(rental_id || ':' ||
                    COALESCE(return_date::text, 'NULL'), ',' ORDER BY rental_id), '')),
               p_run_id
          FROM public.rental
         WHERE rental_date >= v_from AND rental_date < v_to;

        INSERT INTO dw.rpt_source_fingerprint(
            period, table_name, row_count, sum_amount, min_pk, max_pk, checksum, run_id)
        SELECT p_period, 'dw.dim_store', count(*), NULL, min(store_id), max(store_id),
               md5(COALESCE(string_agg(store_id || ':' || store_status, ',' ORDER BY store_id), '')),
               p_run_id
          FROM dw.dim_store;

        dw.pkg_etl_core.log_end(p_run_id, 'take_fingerprint', 'OK', NULL, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'take_fingerprint', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    -- 重新采集并与该期间最早一次指纹比对，返回不一致的表数量。
    -- 0 = 源数据自冻结以来未变动；> 0 = 已变动，披露值需要重算。
    FUNCTION verify_fingerprint(p_period varchar2) RETURN integer IS
        v_diff integer;
    BEGIN
        take_fingerprint(p_period, 'VERIFY_' || p_period);

        SELECT count(*) INTO v_diff
          FROM (SELECT table_name,
                       min(taken_at) AS first_at,
                       max(taken_at) AS last_at
                  FROM dw.rpt_source_fingerprint
                 WHERE period = p_period
                 GROUP BY table_name) t
          JOIN dw.rpt_source_fingerprint f1
            ON f1.period = p_period AND f1.table_name = t.table_name AND f1.taken_at = t.first_at
          JOIN dw.rpt_source_fingerprint f2
            ON f2.period = p_period AND f2.table_name = t.table_name AND f2.taken_at = t.last_at
         WHERE f1.checksum <> f2.checksum
            OR f1.row_count <> f2.row_count
            OR COALESCE(f1.sum_amount, -1) <> COALESCE(f2.sum_amount, -1);

        RETURN v_diff;
    END;

    -- 冻结期间。两道硬闸门，均不留后门：
    --   闸门 1：该期间存在 CRITICAL 级 DQ 结论 -> 拒绝
    --   闸门 2：存在未 APPROVED 的口径定义 -> 拒绝
    PROCEDURE close_period(p_period varchar2, p_run_id varchar2, p_closed_by varchar2) IS
        v_from       date := to_date(p_period || '-01', 'YYYY-MM-DD');
        v_to         date;
        v_critical   bigint;
        v_unapproved bigint;
        v_next_ver   integer;
        v_def_ver    integer;
        v_status     varchar2(16);
    BEGIN
        v_to := (v_from + interval '1 month')::date;
        dw.pkg_etl_core.log_start(p_run_id, 'close_period');

        -- 用聚合而非裸 SELECT INTO：A 兼容模式下查询无结果会报
        -- "query returned no rows when process INTO"，不会把变量置 NULL。
        -- 聚合函数恒返回一行，故新期间（无 rpt_period_close 行）也能安全取默认值。
        SELECT COALESCE(max(status), 'OPEN') INTO v_status
          FROM dw.rpt_period_close WHERE period = p_period;
        IF v_status = 'CLOSED' THEN
            RAISE_APPLICATION_ERROR(-20041,
                'close_period: 期间 ' || p_period || ' 已 CLOSED。'
                || '修正披露请用 recompute_period 产生新 snapshot_version。');
        END IF;

        dw.pkg_dq.run_all(p_run_id, v_from, v_to);

        SELECT count(*) INTO v_critical
          FROM dw.dq_check_result
         WHERE run_id = p_run_id AND severity = 'CRITICAL';
        IF v_critical > 0 THEN
            RAISE_APPLICATION_ERROR(-20042,
                'close_period 拒绝：期间 ' || p_period || ' 存在 ' || v_critical
                || ' 条 CRITICAL 级数据质量问题。披露层要求 0 CRITICAL，无 force 后门。');
        END IF;

        SELECT count(*) INTO v_unapproved
          FROM dw.rpt_metric_def WHERE status <> 'APPROVED';
        IF v_unapproved > 0 THEN
            RAISE_APPLICATION_ERROR(-20043,
                'close_period 拒绝：存在 ' || v_unapproved
                || ' 条未批准(APPROVED)的口径定义。未签字口径不得对外披露 —— '
                || '见 sqls/dw/docs/metric-definitions.md 的 B1~B5。');
        END IF;

        SELECT COALESCE(max(version), 1) INTO v_def_ver FROM dw.rpt_metric_def;
        SELECT COALESCE(max(snapshot_version), 0) + 1 INTO v_next_ver
          FROM dw.rpt_disclosure_snapshot WHERE period = p_period;

        INSERT INTO dw.rpt_disclosure_snapshot(
            period, snapshot_version, metric_code, metric_value, metric_def_version, run_id)
        SELECT p_period, v_next_ver, 'REVENUE_TOTAL', COALESCE(sum(amount), 0), v_def_ver, p_run_id
          FROM dw.dws_sales_month_store
         WHERE stat_month = v_from AND store_status = 'ACTIVE';

        INSERT INTO dw.rpt_disclosure_snapshot(
            period, snapshot_version, metric_code, metric_value, metric_def_version, run_id)
        SELECT p_period, v_next_ver, 'DISCLOSED_STORE_COUNT', count(*), v_def_ver, p_run_id
          FROM dw.dim_store WHERE store_status = 'ACTIVE';

        INSERT INTO dw.rpt_disclosure_snapshot(
            period, snapshot_version, metric_code, metric_value, metric_def_version, run_id)
        SELECT p_period, v_next_ver, 'PAYMENT_COUNT', COALESCE(sum(pay_cnt), 0), v_def_ver, p_run_id
          FROM dw.dws_sales_month_store
         WHERE stat_month = v_from AND store_status = 'ACTIVE';

        take_fingerprint(p_period, p_run_id);

        INSERT INTO dw.rpt_period_close(period, status, metric_def_version, run_id,
                                        closed_by, closed_at)
        VALUES (p_period, 'CLOSED', v_def_ver, p_run_id, p_closed_by, now())
        ON DUPLICATE KEY UPDATE status = 'CLOSED', metric_def_version = v_def_ver,
                                run_id = p_run_id, closed_by = p_closed_by,
                                closed_at = now(), updated_at = now();

        dw.pkg_etl_core.log_end(p_run_id, 'close_period', 'OK', NULL, NULL, NULL);
        RAISE NOTICE 'close_period(%): snapshot_version=% 已冻结', p_period, v_next_ver;
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'close_period', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    -- 重算。只产生 snapshot_version + 1，旧版本永久保留（会计追溯重述）。
    -- 同时重采指纹并把与首次冻结的差异写入 dq_check_result，形成审计线索。
    PROCEDURE recompute_period(p_period varchar2, p_run_id varchar2, p_reason text) IS
        v_from     date := to_date(p_period || '-01', 'YYYY-MM-DD');
        v_next_ver integer;
        v_def_ver  integer;
        v_fp_diff  integer;
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'recompute_period');

        v_fp_diff := verify_fingerprint(p_period);
        IF v_fp_diff > 0 THEN
            dw.pkg_dq.emit(p_run_id, p_period, 'FINGERPRINT_MISMATCH', 'CRITICAL',
                           '0 tables changed', v_fp_diff::text, p_reason);
        END IF;

        SELECT COALESCE(max(version), 1) INTO v_def_ver FROM dw.rpt_metric_def;
        SELECT COALESCE(max(snapshot_version), 0) + 1 INTO v_next_ver
          FROM dw.rpt_disclosure_snapshot WHERE period = p_period;

        INSERT INTO dw.rpt_disclosure_snapshot(
            period, snapshot_version, metric_code, metric_value, metric_text,
            metric_def_version, run_id)
        SELECT p_period, v_next_ver, 'REVENUE_TOTAL', COALESCE(sum(amount), 0),
               p_reason, v_def_ver, p_run_id
          FROM dw.dws_sales_month_store
         WHERE stat_month = v_from AND store_status = 'ACTIVE';

        INSERT INTO dw.rpt_disclosure_snapshot(
            period, snapshot_version, metric_code, metric_value, metric_text,
            metric_def_version, run_id)
        SELECT p_period, v_next_ver, 'DISCLOSED_STORE_COUNT', count(*),
               p_reason, v_def_ver, p_run_id
          FROM dw.dim_store WHERE store_status = 'ACTIVE';

        INSERT INTO dw.rpt_disclosure_snapshot(
            period, snapshot_version, metric_code, metric_value, metric_text,
            metric_def_version, run_id)
        SELECT p_period, v_next_ver, 'PAYMENT_COUNT', COALESCE(sum(pay_cnt), 0),
               p_reason, v_def_ver, p_run_id
          FROM dw.dws_sales_month_store
         WHERE stat_month = v_from AND store_status = 'ACTIVE';

        dw.pkg_etl_core.log_end(p_run_id, 'recompute_period', 'OK', NULL, NULL, NULL);
        RAISE NOTICE 'recompute_period(%): snapshot_version=%, fingerprint_diff=%',
            p_period, v_next_ver, v_fp_diff;
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'recompute_period', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

END pkg_disclose;
/
