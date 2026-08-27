-- Phase 0 — PKG_ETL_CORE：运行日志 / 水位线 / 分区哨兵
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §5.1 / §6.1-F3 / §6.2
-- 幂等：CREATE OR REPLACE，可重复执行。

\set ON_ERROR_STOP on
SET check_function_bodies = false;

CREATE OR REPLACE PACKAGE dw.pkg_etl_core IS
    FUNCTION new_run_id(p_prefix varchar2) RETURN varchar2;

    PROCEDURE log_start(p_run_id varchar2, p_step varchar2);
    PROCEDURE log_end(p_run_id varchar2, p_step varchar2, p_status varchar2,
                      p_rows bigint, p_err_code varchar2, p_err_msg text);

    PROCEDURE ensure_partitions(p_table varchar2, p_months_ahead integer,
                               p_schema varchar2 DEFAULT 'public');

    PROCEDURE plan_increment(p_source varchar2,
                             o_id_from OUT bigint, o_id_to OUT bigint,
                             o_ts_from OUT timestamptz, o_ts_to OUT timestamptz);

    PROCEDURE commit_increment(p_source varchar2, p_id_to bigint,
                               p_ts_to timestamptz, p_run_id varchar2);

    PROCEDURE set_watermark(p_source varchar2, p_id_value bigint,
                            p_ts_value timestamptz, p_run_id varchar2);
END pkg_etl_core;
/

CREATE OR REPLACE PACKAGE BODY dw.pkg_etl_core IS

    FUNCTION new_run_id(p_prefix varchar2) RETURN varchar2 IS
    BEGIN
        RETURN p_prefix || '_' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS');
    END;

    -- 自治事务：主事务失败回滚后，"为什么失败"的证据必须留存。
    PROCEDURE log_start(p_run_id varchar2, p_step varchar2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO dw.etl_run_log(run_id, step_name, status)
        VALUES (p_run_id, p_step, 'STARTED');
    END;

    PROCEDURE log_end(p_run_id varchar2, p_step varchar2, p_status varchar2,
                      p_rows bigint, p_err_code varchar2, p_err_msg text) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        UPDATE dw.etl_run_log
           SET status = p_status, ended_at = now(), affected_rows = p_rows,
               err_code = p_err_code, err_msg = p_err_msg
         WHERE log_id = (SELECT max(log_id) FROM dw.etl_run_log
                          WHERE run_id = p_run_id AND step_name = p_step);
    END;

    -- 分区哨兵。三条路径，由"是否有 MAXVALUE 兜底分区"与"是否列存"共同决定：
    --   A) 无 MAXVALUE            -> ADD PARTITION
    --   B) 有 MAXVALUE 且行存      -> SPLIT PARTITION + RENAME（保留 pmax 内已有行）
    --   C) 有 MAXVALUE 且列存      -> DROP pmax + ADD 月分区 + 重建 pmax
    --                               （列存不支持 SPLIT，故要求 pmax 必须为空）
    --
    -- 为什么所有分区表都应保留 MAXVALUE 兜底分区（实测依据）：
    --   1) 无兜底分区时，超出最大边界的**插入**直接报错；
    --   2) 更隐蔽的是，谓词区间完全超出最大边界的**查询**也会报
    --      "Fail to find partition from sequence."，而不是返回 0 行。
    --      DQ 与报表查询会因此在合法的"未来期间"上崩掉。
    --
    -- 路径 B 的 SPLIT 不允许结果分区复用被拆分区的名字（报 "resulting partition
    -- name conflicts with that of an existing partition"），故先切成临时名再改回。
    -- 路径 C 的 DROP 必须带 UPDATE GLOBAL INDEX，否则全局索引会被置为
    -- indisusable=false（G18，实测已发生过）。
    --
    -- 边界一律以 UTC 渲染为 'YYYY-MM-DD HH24:MI:SS+00'：源表分区边界字面量是
    -- UTC，且 to_char 的 'OF' 时区格式在本版本不生效（会输出字面量 "OF"）。
    -- 月份运算也在 UTC 无时区域内进行，避免会话时区 DST 导致边界漂移。
    PROCEDURE ensure_partitions(p_table varchar2, p_months_ahead integer,
                               p_schema varchar2 DEFAULT 'public') IS
        v_qualified      varchar2(256) := p_schema || '.' || p_table;
        v_max_part_name  varchar2(128) := p_table || '_pmax';
        v_has_max        boolean;
        v_is_column      boolean;
        v_max_rows       bigint;
        v_last_boundary  timestamp;
        v_target         timestamp;
        v_cursor         timestamp;
        v_part_name      varchar2(128);
        v_tmp_name       varchar2(128);
        v_bound_literal  varchar2(64);
        v_created        integer := 0;
    BEGIN
        SELECT EXISTS (SELECT 1 FROM pg_partition
                        WHERE parentid = v_qualified::regclass
                          AND parttype = 'p' AND relname = v_max_part_name)
          INTO v_has_max;

        SELECT COALESCE(array_to_string(reloptions, ',') LIKE '%orientation=column%', false)
          INTO v_is_column
          FROM pg_class WHERE oid = v_qualified::regclass;

        SELECT max(boundaries[1]::timestamptz) AT TIME ZONE 'UTC' INTO v_last_boundary
          FROM pg_partition
         WHERE parentid = v_qualified::regclass
           AND parttype = 'p'
           AND boundaries[1] IS NOT NULL;

        IF v_last_boundary IS NULL THEN
            RAISE_APPLICATION_ERROR(-20010,
                'ensure_partitions: no bounded partition found on ' || v_qualified);
        END IF;

        v_target := date_trunc('month', now() AT TIME ZONE 'UTC')
                    + ((p_months_ahead + 1) || ' month')::interval;

        IF v_last_boundary >= v_target THEN
            RAISE NOTICE 'ensure_partitions(%): created 0 partition(s), already covers % UTC',
                v_qualified, v_target;
            RETURN;
        END IF;

        -- 路径 C 前置：列存表要拆 pmax 只能靠 DROP，故 pmax 必须为空，
        -- 否则会静默丢数据。非空时中止并要求人工先迁移。
        IF v_has_max AND v_is_column THEN
            EXECUTE IMMEDIATE 'SELECT count(*) FROM ' || v_qualified
                              || ' PARTITION (' || v_max_part_name || ')' INTO v_max_rows;
            IF v_max_rows > 0 THEN
                RAISE_APPLICATION_ERROR(-20012,
                    'ensure_partitions: ' || v_qualified || ' 兜底分区非空(' || v_max_rows
                    || ' 行)，列存表无法 SPLIT，请先迁移这些行再重试');
            END IF;
            EXECUTE IMMEDIATE 'ALTER TABLE ' || v_qualified
                || ' DROP PARTITION ' || v_max_part_name || ' UPDATE GLOBAL INDEX';
        END IF;

        v_cursor := v_last_boundary;
        WHILE v_cursor < v_target LOOP
            v_part_name     := p_table || '_p' || to_char(v_cursor, 'YYYY_MM');
            v_tmp_name      := v_part_name || '_tmp';
            v_bound_literal := to_char(v_cursor + interval '1 month',
                                       'YYYY-MM-DD HH24:MI:SS') || '+00';

            IF v_has_max AND NOT v_is_column THEN
                EXECUTE IMMEDIATE 'ALTER TABLE ' || v_qualified
                    || ' SPLIT PARTITION ' || v_max_part_name
                    || ' AT (''' || v_bound_literal || ''')'
                    || ' INTO (PARTITION ' || v_part_name || ', PARTITION ' || v_tmp_name || ')'
                    || ' UPDATE GLOBAL INDEX';
                EXECUTE IMMEDIATE 'ALTER TABLE ' || v_qualified
                    || ' RENAME PARTITION ' || v_tmp_name || ' TO ' || v_max_part_name;
            ELSE
                EXECUTE IMMEDIATE 'ALTER TABLE ' || v_qualified
                    || ' ADD PARTITION ' || v_part_name
                    || ' VALUES LESS THAN (''' || v_bound_literal || ''')';
            END IF;

            v_created := v_created + 1;
            v_cursor  := v_cursor + interval '1 month';
        END LOOP;

        IF v_has_max AND v_is_column THEN
            EXECUTE IMMEDIATE 'ALTER TABLE ' || v_qualified
                || ' ADD PARTITION ' || v_max_part_name || ' VALUES LESS THAN (MAXVALUE)';
        END IF;

        RAISE NOTICE 'ensure_partitions(%): created % partition(s), target boundary % UTC',
            v_qualified, v_created, v_target;
    END;

    -- 规划增量窗口。返回 ID 与 TS 两组边界，供调用方按"双轨"取增量集合。
    --
    -- 为什么必须双轨（payment 无 last_update，缺陷 S3）：
    --   只用 payment_id   -> 漏掉"id 更大但 payment_date 更早"的补录行（夹具 CV5）
    --   只用 payment_date -> 漏掉同一天内、水位线采集之后提交的并发插入（CV10）
    --
    -- 两个边界的设计要点：
    --   o_id_to 在**抽取前**捕获当前最大 id，抽取只到该值为止，成功后才把水位线
    --   推进到它。若改成抽取后取 max，会把运行期间新插入的行"算作已处理"而漏掉。
    --   o_ts_to 减去 safety_margin，规避"事务开始早于 now() 但提交晚于水位线采集"
    --   的经典漏行。
    --   o_ts_from 再回退 lookback_days，用于回补迟到数据。
    --
    -- ⚠️ ID 轨的前提假设：**所有写入方共用同一单调序列**。
    --   实测隐患：若有写入方使用显式的、高于当前序列值的 id（数据迁移、造数夹具、
    --   多源合并都会这样做），水位线会被永久抬高到那个高位值，之后所有走序列的
    --   正常插入（id 更小）都会被 ID 轨**静默跳过**。
    --   实测复现：夹具用 9e8 段 id → 水位线被推到 900099999 → 后续 id 900097002
    --   的补录行既不满足 ID 轨（900097002 < 900099999）也不在 TS 回溯窗内
    --   （日期为 2024-05）→ 双轨全漏，最终由月度全量对账 RECON_DWD_VS_BASE 捕获。
    --   运维要求：① 造数/迁移后必须重置水位线；② 月度全量对账不可省（§6.3）。
    PROCEDURE plan_increment(p_source varchar2,
                             o_id_from OUT bigint, o_id_to OUT bigint,
                             o_ts_from OUT timestamptz, o_ts_to OUT timestamptz) IS
        v_wm dw.etl_watermark%ROWTYPE;
        v_exists integer;
    BEGIN
        -- 先用聚合确认存在性再取行：A 兼容模式下裸 SELECT INTO 在无结果时会报
        -- "query returned no rows when process INTO"，导致下面的友好报错永远走不到。
        SELECT count(*) INTO v_exists FROM dw.etl_watermark WHERE source_name = p_source;
        IF v_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20013,
                'plan_increment: unknown source ' || p_source);
        END IF;
        SELECT * INTO v_wm FROM dw.etl_watermark WHERE source_name = p_source;

        o_ts_to   := now() - v_wm.safety_margin;
        o_ts_from := COALESCE(v_wm.wm_ts_value, timestamptz '1970-01-01')
                     - (v_wm.lookback_days || ' day')::interval;
        o_id_from := COALESCE(v_wm.wm_id_value, 0);

        IF v_wm.src_id_col IS NOT NULL AND v_wm.src_table IS NOT NULL THEN
            EXECUTE IMMEDIATE 'SELECT COALESCE(max(' || v_wm.src_id_col || '), 0) FROM '
                              || v_wm.src_table INTO o_id_to;
        ELSE
            o_id_to := 0;
        END IF;

        RAISE NOTICE 'plan_increment(%): id (%, %], ts [%, %)',
            p_source, o_id_from, o_id_to, o_ts_from, o_ts_to;
    END;

    -- 提交增量：只有构建成功后才推进水位线。失败时不调用本过程，
    -- 下次运行会用原水位线重跑（配合 DELETE+INSERT 幂等，重跑安全）。
    -- 用 GREATEST 防止并发或乱序调用把水位线回退。
    PROCEDURE commit_increment(p_source varchar2, p_id_to bigint,
                               p_ts_to timestamptz, p_run_id varchar2) IS
    BEGIN
        UPDATE dw.etl_watermark
           SET wm_id_value = GREATEST(COALESCE(wm_id_value, 0), COALESCE(p_id_to, 0)),
               wm_ts_value = GREATEST(COALESCE(wm_ts_value, timestamptz '1970-01-01'), p_ts_to),
               last_run_id = p_run_id,
               updated_at  = now()
         WHERE source_name = p_source;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20014,
                'commit_increment: unknown source ' || p_source);
        END IF;
    END;

    PROCEDURE set_watermark(p_source varchar2, p_id_value bigint,
                            p_ts_value timestamptz, p_run_id varchar2) IS
    BEGIN
        UPDATE dw.etl_watermark
           SET wm_id_value = p_id_value, wm_ts_value = p_ts_value,
               last_run_id = p_run_id, updated_at = now()
         WHERE source_name = p_source;

        IF SQL%ROWCOUNT = 0 THEN
            RAISE_APPLICATION_ERROR(-20011,
                'set_watermark: unknown source ' || p_source);
        END IF;
    END;

END pkg_etl_core;
/
