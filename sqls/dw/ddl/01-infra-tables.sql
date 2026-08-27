-- Phase 0 — 数仓旁路基础表
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §5.3.1 / §6.2 / 附录 A
-- 幂等：可重复执行。

\set ON_ERROR_STOP on

CREATE SCHEMA IF NOT EXISTS dw;

-- 运行日志。由 PKG_ETL_CORE 以自治事务写入：主事务回滚后失败证据仍需留存。
CREATE SEQUENCE IF NOT EXISTS dw.etl_run_log_seq;
CREATE TABLE IF NOT EXISTS dw.etl_run_log (
    log_id        bigint       NOT NULL DEFAULT nextval('dw.etl_run_log_seq'::regclass),
    run_id        varchar(64)  NOT NULL,
    step_name     varchar(128) NOT NULL,
    status        varchar(16)  NOT NULL,
    started_at    timestamp with time zone NOT NULL DEFAULT now(),
    ended_at      timestamp with time zone,
    affected_rows bigint,
    err_code      varchar(32),
    err_msg       text,
    CONSTRAINT etl_run_log_pk PRIMARY KEY (log_id),
    CONSTRAINT etl_run_log_status_ck CHECK (status IN ('STARTED','OK','WARN','FAILED'))
);
CREATE INDEX IF NOT EXISTS idx_etl_run_log_run ON dw.etl_run_log (run_id, step_name);

-- 增量水位线。payment 无 last_update，必须 ID+TS 双轨：
--   单靠 payment_id 会漏"id 更大但 payment_date 更早"的补录行；
--   单靠 payment_date 会漏同一天内的并发插入。
-- safety_margin 用于规避"事务开始早于 now() 但提交晚于水位线采集"的漏行。
--
-- src_table / src_id_col / src_ts_col 使水位线推进可数据驱动，避免把源表列名
-- 硬编码进存储过程（新增数据源只需插一行配置）。
CREATE TABLE IF NOT EXISTS dw.etl_watermark (
    source_name   varchar(64)  NOT NULL,
    wm_type       varchar(8)   NOT NULL,
    src_table     varchar(128),
    src_id_col    varchar(64),
    src_ts_col    varchar(64),
    wm_id_value   bigint,
    wm_ts_value   timestamp with time zone,
    lookback_days integer      NOT NULL DEFAULT 7,
    safety_margin interval     NOT NULL DEFAULT interval '5 minutes',
    last_run_id   varchar(64),
    updated_at    timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT etl_watermark_pk PRIMARY KEY (source_name),
    CONSTRAINT etl_watermark_type_ck CHECK (wm_type IN ('ID','TS','ID_TS'))
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='dw.etl_watermark'::regclass
                    AND attname='src_table' AND attnum>0) THEN
        ALTER TABLE dw.etl_watermark ADD COLUMN src_table  varchar(128);
        ALTER TABLE dw.etl_watermark ADD COLUMN src_id_col varchar(64);
        ALTER TABLE dw.etl_watermark ADD COLUMN src_ts_col varchar(64);
    END IF;
END $$;

-- 数据质量稽核结果。闸门语义不对称：C1/C2/C3 见 CRITICAL 不阻塞（打 dq_flag
-- 透出），C4 披露层要求 0 CRITICAL 才允许 close_period。
CREATE SEQUENCE IF NOT EXISTS dw.dq_check_result_seq;
CREATE TABLE IF NOT EXISTS dw.dq_check_result (
    check_id    bigint       NOT NULL DEFAULT nextval('dw.dq_check_result_seq'::regclass),
    run_id      varchar(64)  NOT NULL,
    period      varchar(16),
    rule_code   varchar(64)  NOT NULL,
    severity    varchar(16)  NOT NULL,
    expected    text,
    actual      text,
    sample_keys text,
    checked_at  timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT dq_check_result_pk PRIMARY KEY (check_id),
    CONSTRAINT dq_check_result_sev_ck CHECK (severity IN ('INFO','WARN','CRITICAL'))
);
CREATE INDEX IF NOT EXISTS idx_dq_check_result_run ON dw.dq_check_result (run_id, severity);

-- 重型 SQL 任务队列（方案 §5.3 的 O1 架构）。
--
-- 存在理由：openGauss 官方明确"存储过程和函数内的查询不支持并行执行(SMP)"，
-- 企业版亦然。若把 1 亿行级聚合写在存储过程体内，将永久放弃多核加速。
-- 故由库内 PKG_ORCH 负责编排（生成 SQL + 顺序 + 依赖），外部 worker 负责把
-- sql_text 作为**顶层语句**提交以保留 SMP。
--
-- UNIQUE(run_id, step_name) 是幂等入队护栏：PKG_ORCH 重复入队不产生重复任务
-- （配合 INSERT ... ON DUPLICATE KEY UPDATE NOTHING）。
CREATE SEQUENCE IF NOT EXISTS dw.etl_task_queue_seq;
CREATE TABLE IF NOT EXISTS dw.etl_task_queue (
    task_id       bigint       NOT NULL DEFAULT nextval('dw.etl_task_queue_seq'::regclass),
    run_id        varchar(64)  NOT NULL,
    step_name     varchar(128) NOT NULL,
    seq_no        integer      NOT NULL,
    depends_on    integer,
    sql_text      text         NOT NULL,
    status        varchar(16)  NOT NULL DEFAULT 'PENDING',
    claimed_by    varchar(64),
    claimed_at    timestamp with time zone,
    started_at    timestamp with time zone,
    finished_at   timestamp with time zone,
    affected_rows bigint,
    attempt       integer      NOT NULL DEFAULT 0,
    max_attempt   integer      NOT NULL DEFAULT 3,
    err_code      varchar(32),
    err_msg       text,
    created_at    timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT etl_task_queue_pk PRIMARY KEY (task_id),
    CONSTRAINT etl_task_queue_uk UNIQUE (run_id, step_name),
    CONSTRAINT etl_task_queue_status_ck CHECK (status IN
        ('PENDING','CLAIMED','RUNNING','SUCCEEDED','FAILED','SKIPPED'))
);
CREATE INDEX IF NOT EXISTS idx_etl_task_queue_claim
    ON dw.etl_task_queue (status, run_id, seq_no);

-- 水位线初始行。payment 用 ID_TS 双轨（无 last_update）；其余源表用 last_update。
-- ON DUPLICATE KEY UPDATE NOTHING 保证重复执行不覆盖已推进的水位线。
INSERT INTO dw.etl_watermark(source_name, wm_type, lookback_days) VALUES
    ('payment',       'ID_TS', 7),
    ('rental',        'TS',    7),
    ('customer',      'TS',    3),
    ('inventory',     'TS',    3),
    ('film',          'TS',    3),
    ('film_actor',    'TS',    3),
    ('film_category', 'TS',    3),
    ('actor',         'TS',    3),
    ('category',      'TS',    3),
    ('language',      'TS',    3),
    ('staff',         'TS',    3),
    ('store',         'TS',    3),
    ('address',       'TS',    3),
    ('city',          'TS',    3),
    ('country',       'TS',    3)
ON DUPLICATE KEY UPDATE NOTHING;

-- src_* 是配置（可安全刷新），wm_* 是状态（绝不可在此覆盖，否则会导致
-- 全量重扫或数据缺口）。故配置列用独立 UPDATE 而不放进上面的 INSERT。
UPDATE dw.etl_watermark w SET
    src_table  = c.tbl,
    src_id_col = c.id_col,
    src_ts_col = c.ts_col
FROM (VALUES
    ('payment',       'public.payment',       'payment_id', 'payment_date'),
    ('rental',        'public.rental',        'rental_id',  'last_update'),
    ('customer',      'public.customer',      'customer_id','last_update'),
    ('inventory',     'public.inventory',     'inventory_id','last_update'),
    ('film',          'public.film',          'film_id',    'last_update'),
    ('film_actor',    'public.film_actor',     NULL,        'last_update'),
    ('film_category', 'public.film_category',  NULL,        'last_update'),
    ('actor',         'public.actor',         'actor_id',   'last_update'),
    ('category',      'public.category',      'category_id','last_update'),
    ('language',      'public.language',      'language_id','last_update'),
    ('staff',         'public.staff',         'staff_id',   'last_update'),
    ('store',         'public.store',         'store_id',   'last_update'),
    ('address',       'public.address',       'address_id', 'last_update'),
    ('city',          'public.city',          'city_id',    'last_update'),
    ('country',       'public.country',       'country_id', 'last_update')
) AS c(src, tbl, id_col, ts_col)
WHERE w.source_name = c.src;

SELECT 'infra' AS component,
       CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/4)' END AS result,
       string_agg(tablename, ', ' ORDER BY tablename) AS detail
FROM pg_tables
WHERE schemaname = 'dw'
  AND tablename IN ('etl_run_log','etl_watermark','dq_check_result','etl_task_queue')
UNION ALL
SELECT 'watermark seed',
       CASE WHEN count(*) = 15 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/15)' END,
       'ID_TS: ' || count(*) FILTER (WHERE wm_type = 'ID_TS')
FROM dw.etl_watermark;
