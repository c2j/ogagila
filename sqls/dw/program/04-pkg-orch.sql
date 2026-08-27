-- Phase 2 — PKG_ORCH：库内编排（双模式）
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §5.3 / DD9 / DD10 / §5.3.1
--
-- 调度形态（R4 已确认）：**触发在外部、编排在库内**。外部 cron/CronJob 只负责
-- 触发与重试，步骤顺序与依赖关系全部定义在本包内。
--
-- 双模式的存在理由 —— 让方案 §10.1-Q2 从"架构选择"降级为"配置开关"：
--   DIRECT：直接调用 build_* 过程。最简单、纯库内。
--           代价：openGauss 官方明确"存储过程和函数内的查询不支持并行执行(SMP)"，
--           企业版亦然，故重型聚合拿不到多核加速。
--   QUEUE ：把重型 DELETE+INSERT 的**裸 SQL 文本**投递到 dw.etl_task_queue，
--           由外部 worker 以**顶层语句**提交，从而保留 SMP。
--           代价：多一个 worker 进程；SQL 文本存在两处定义（由等价性断言守护）。
--
-- 轻量步骤（分区哨兵、DIM 构建）无论哪种模式都走 DIRECT：它们是 DDL / 小表全量
-- 重建，不是 SMP 的受益对象，且 DWD 依赖 DIM 必须先完成。

\set ON_ERROR_STOP on
SET check_function_bodies = false;

CREATE OR REPLACE PACKAGE dw.pkg_orch IS
    PROCEDURE enqueue(p_run_id varchar2, p_step varchar2, p_seq integer,
                      p_depends_on integer, p_sql text);
    PROCEDURE run_daily  (p_date date, p_run_id varchar2, p_mode varchar2 DEFAULT 'DIRECT');
    PROCEDURE run_monthly(p_period date, p_run_id varchar2, p_mode varchar2 DEFAULT 'DIRECT');
END pkg_orch;
/

CREATE OR REPLACE PACKAGE BODY dw.pkg_orch IS

    -- 幂等入队（契约 K5）：UNIQUE(run_id, step_name) + ON DUPLICATE KEY UPDATE NOTHING
    -- 保证同一批次重复编排不产生重复任务。
    PROCEDURE enqueue(p_run_id varchar2, p_step varchar2, p_seq integer,
                      p_depends_on integer, p_sql text) IS
    BEGIN
        INSERT INTO dw.etl_task_queue(run_id, step_name, seq_no, depends_on, sql_text)
        VALUES (p_run_id, p_step, p_seq, p_depends_on, p_sql)
        ON DUPLICATE KEY UPDATE NOTHING;
    END;

    PROCEDURE run_daily(p_date date, p_run_id varchar2, p_mode varchar2 DEFAULT 'DIRECT') IS
        v_rows   integer;
        v_months integer;
        v_status varchar2(16);
        v_from   date := date_trunc('month', p_date)::date;
        v_to     date := (date_trunc('month', p_date) + interval '1 month')::date;
    BEGIN
        IF p_mode NOT IN ('DIRECT', 'QUEUE') THEN
            RAISE_APPLICATION_ERROR(-20020,
                'run_daily: p_mode must be DIRECT or QUEUE, got ' || p_mode);
        END IF;

        dw.pkg_etl_core.log_start(p_run_id, 'run_daily[' || p_mode || ']');

        -- 步骤 1-2 恒为 DIRECT。分区哨兵必须最先跑：dw 列存事实表虽有 MAXVALUE
        -- 兜底分区，但兜底分区非空会触发 PARTITION_OVERFLOW(CRITICAL)。
        dw.pkg_etl_core.ensure_partitions('payment', 3);
        dw.pkg_etl_core.ensure_partitions('dwd_fact_payment', 3, 'dw');
        dw.pkg_etl_core.ensure_partitions('dwd_fact_rental',  3, 'dw');

        dw.pkg_dim.build_all(v_from, v_to, p_run_id);

        IF p_mode = 'DIRECT' THEN
            dw.pkg_dwd.build_payment_incremental(p_run_id, v_rows, v_months);
            dw.pkg_dwd.build_rental_incremental (p_run_id, v_rows, v_months);
            dw.pkg_dq.run_all(p_run_id, v_from, v_to);
        ELSE
            -- 严格串行链（seq 3 -> 4 -> 5）。契约 K7：某步终态 FAILED 时其下游
            -- 全部置 SKIPPED。若让 DQ 同时依赖 3 和 4 而 depends_on 只能指向一个
            -- seq_no，就会出现"3 失败但 4 成功 -> DQ 仍执行"的错误放行。
            enqueue(p_run_id, 'dwd_payment', 3, NULL,
                    dw.pkg_dwd.gen_payment_sql(v_from, v_to, p_run_id));
            enqueue(p_run_id, 'dwd_rental',  4, 3,
                    dw.pkg_dwd.gen_rental_sql(v_from, v_to, p_run_id));
            -- DQ 以 CALL 投递：它不是 SMP 的主要受益者。若其全量对账在规模上
            -- 成为瓶颈，可在 Phase 4 把 recon 查询单独提成裸 SQL。
            enqueue(p_run_id, 'dq_run_all', 5, 4,
                    'CALL dw.pkg_dq.run_all(' || quote_literal(p_run_id) || ', '
                    || quote_literal(to_char(v_from, 'YYYY-MM-DD')) || '::date, '
                    || quote_literal(to_char(v_to,   'YYYY-MM-DD')) || '::date);');
        END IF;

        dw.pkg_etl_core.log_end(p_run_id, 'run_daily[' || p_mode || ']', 'OK', NULL, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'run_daily[' || p_mode || ']', 'FAILED', 0,
                                SQLSTATE, SQLERRM);
        RAISE;
    END;

    -- 月度全量重建 + 对账。这是增量方案的必需兜底（§6.3）：增量原理上无法感知
    -- 源侧物理删除，也无法覆盖超出 lookback 的迟到数据（实测隐患 G29）。
    PROCEDURE run_monthly(p_period date, p_run_id varchar2, p_mode varchar2 DEFAULT 'DIRECT') IS
        v_rows   integer;
        v_status varchar2(16);
        v_from   date := date_trunc('month', p_period)::date;
        v_to     date := (date_trunc('month', p_period) + interval '1 month')::date;
    BEGIN
        IF p_mode NOT IN ('DIRECT', 'QUEUE') THEN
            RAISE_APPLICATION_ERROR(-20021,
                'run_monthly: p_mode must be DIRECT or QUEUE, got ' || p_mode);
        END IF;

        dw.pkg_etl_core.log_start(p_run_id, 'run_monthly[' || p_mode || ']');

        dw.pkg_dim.build_all(v_from, v_to, p_run_id);

        IF p_mode = 'DIRECT' THEN
            dw.pkg_dwd.build_dwd_fact_payment(v_from, v_to, p_run_id, v_rows, v_status);
            dw.pkg_dwd.build_dwd_fact_rental (v_from, v_to, p_run_id, v_rows, v_status);
            dw.pkg_dq.run_all(p_run_id, v_from, v_to);
        ELSE
            enqueue(p_run_id, 'monthly_payment', 3, NULL,
                    dw.pkg_dwd.gen_payment_sql(v_from, v_to, p_run_id));
            enqueue(p_run_id, 'monthly_rental',  4, 3,
                    dw.pkg_dwd.gen_rental_sql(v_from, v_to, p_run_id));
            enqueue(p_run_id, 'monthly_dq', 5, 4,
                    'CALL dw.pkg_dq.run_all(' || quote_literal(p_run_id) || ', '
                    || quote_literal(to_char(v_from, 'YYYY-MM-DD')) || '::date, '
                    || quote_literal(to_char(v_to,   'YYYY-MM-DD')) || '::date);');
        END IF;

        dw.pkg_etl_core.log_end(p_run_id, 'run_monthly[' || p_mode || ']', 'OK', NULL, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'run_monthly[' || p_mode || ']', 'FAILED', 0,
                                SQLSTATE, SQLERRM);
        RAISE;
    END;

END pkg_orch;
/
