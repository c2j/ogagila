-- Phase 1 — DIM 维度层
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §4.2 / §6.1
-- 口径依据：sqls/dw/docs/metric-definitions.md §1(门店三态) §2(分析截止日) §4(COUNT 口径)
--
-- 存储：行存 + compresstype=2(zstd)。维表体量小，压缩收益已实测（V6）。
-- 列存不适用：维表是点查/小表 join 的对象，且列存不支持外键与部分索引类型。

\set ON_ERROR_STOP on

-- 统一分析截止日（口径文档 §2）。rental 最大日期实测超出 payment 最大日期，
-- 若不统一截止日，最后一期会呈现"有租赁、零收入"的假性收入断崖。
CREATE OR REPLACE VIEW dw.v_analysis_cutoff AS
SELECT LEAST((SELECT max(payment_date) FROM payment),
             (SELECT max(rental_date)  FROM rental)) AS analysis_cutoff;

-- 门店维度。这是全体系唯一的门店口径出口：
-- 禁止任何层直接 FROM store（方案 §12-RK1，最高等级风险）。
--
-- store_status 四态而非文档所述三态：口径文档 §1.1 定义的 ACTIVE/DORMANT/EXCLUDED
-- 未覆盖"无库存但有客户"的组合，故显式增加 UNCLASSIFIED 并由 DQ 规则告警，
-- 而不是静默归入某一态造成口径错误。
CREATE TABLE IF NOT EXISTS dw.dim_store (
    store_id            integer      NOT NULL,
    store_status        varchar(16)  NOT NULL,
    first_business_date date,
    last_business_date  date,
    inv_cnt             bigint       NOT NULL,
    cust_cnt            bigint       NOT NULL,
    staff_cnt           bigint       NOT NULL,
    pay_cnt             bigint       NOT NULL,
    pay_cnt_all_time    bigint       NOT NULL,
    manager_staff_id    integer,
    manager_name        text,
    mgr_is_orphan       boolean      NOT NULL,
    city                text,
    country             text,
    district            text,
    period_from         date         NOT NULL,
    period_to           date         NOT NULL,
    run_id              varchar(64)  NOT NULL,
    built_at            timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT dim_store_pk PRIMARY KEY (store_id),
    CONSTRAINT dim_store_status_ck CHECK (store_status IN
        ('ACTIVE','DORMANT','EXCLUDED','UNCLASSIFIED'))
) WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);
CREATE INDEX IF NOT EXISTS idx_dim_store_status ON dw.dim_store (store_status);

-- pay_cnt 带报告期过滤，pay_cnt_all_time 不带。结构性缺陷（如"有交易但无 staff"，
-- 源库缺陷 D3）必须在**全时段**上检测：若只看报告期，一个历史上有交易、当期无
-- 交易的问题门店会被漏报。两个计数列因此都必需，不可合并。
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_attribute
                    WHERE attrelid = 'dw.dim_store'::regclass
                      AND attname = 'pay_cnt_all_time' AND attnum > 0) THEN
        ALTER TABLE dw.dim_store ADD COLUMN pay_cnt_all_time bigint NOT NULL DEFAULT 0;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS dw.dim_staff (
    staff_id       integer      NOT NULL,
    store_id       integer      NOT NULL,
    full_name      text         NOT NULL,
    email          text,
    active         boolean      NOT NULL,
    pay_cnt        bigint       NOT NULL,
    first_pay_date date,
    last_pay_date  date,
    run_id         varchar(64)  NOT NULL,
    built_at       timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT dim_staff_pk PRIMARY KEY (staff_id)
) WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);
CREATE INDEX IF NOT EXISTS idx_dim_staff_store ON dw.dim_staff (store_id);

-- film_category 是多对多结构。取 min(category_id) 保证确定性，并用
-- multi_category 标记一片多类的情况，避免下钻时金额被重复计入多个品类。
CREATE TABLE IF NOT EXISTS dw.dim_film (
    film_id         integer      NOT NULL,
    title           text         NOT NULL,
    category_id     integer,
    category_name   text,
    multi_category  boolean      NOT NULL,
    rating          text,
    rental_rate     numeric(6,2),
    rental_duration smallint,
    length          smallint,
    language_name   text,
    run_id          varchar(64)  NOT NULL,
    built_at        timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT dim_film_pk PRIMARY KEY (film_id)
) WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);
CREATE INDEX IF NOT EXISTS idx_dim_film_category ON dw.dim_film (category_id);

CREATE TABLE IF NOT EXISTS dw.dim_geo (
    city_id    integer      NOT NULL,
    city       text         NOT NULL,
    country_id integer      NOT NULL,
    country    text         NOT NULL,
    run_id     varchar(64)  NOT NULL,
    built_at   timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT dim_geo_pk PRIMARY KEY (city_id)
) WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);

SELECT 'dim tables' AS component,
       CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/4)' END AS result,
       string_agg(tablename, ', ' ORDER BY tablename) AS detail
FROM pg_tables
WHERE schemaname = 'dw'
  AND tablename IN ('dim_store','dim_staff','dim_film','dim_geo');
