-- Phase 2 — DWS 汇总层（SSOT）
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §4.2 / DD2 / DD4 / DD6
-- 口径依据：sqls/dw/docs/metric-definitions.md §1 §3 §7
--
-- 分层定位：DWS 是全体系唯一的物理事实汇总层。C1 大屏 / C2 中层 / C3 高层 /
-- C4 披露全部从这里派生，口径因此天然一致。
--
-- 存储形态按访问模式分化：
--   日粒度三张表 -> 列存 + RANGE 月分区（大表聚合扫描，与 DWD 一致）
--   月粒度一张表 -> 行存 + Ustore。月表小且会被反复 UPDATE（回补、期间完整性
--     标记变更），Ustore 原地更新、空间不膨胀，正是官方定位的"短频快"场景。
--
-- 与 DWD 相同的三条列存实测约束仍然适用：不支持 SPLIT PARTITION（故保留
-- MAXVALUE 兜底分区并由哨兵走路径 C）、不支持 UNIQUE 索引、不支持 CHECK 约束。

\set ON_ERROR_STOP on

CREATE TABLE IF NOT EXISTS dw.dws_sales_day_store_category (
    stat_date        date          NOT NULL,
    store_id         integer       NOT NULL,
    store_status     varchar(16),
    category_id      integer,
    category_name    text,
    pay_cnt          bigint        NOT NULL,
    amount           numeric(18,2) NOT NULL,
    customer_cnt     bigint        NOT NULL,
    multi_cat_cnt    bigint        NOT NULL,
    dq_flag          boolean       NOT NULL,
    run_id           varchar(64)   NOT NULL,
    built_at         timestamp with time zone NOT NULL DEFAULT now()
) WITH (ORIENTATION = COLUMN, COMPRESSION = HIGH)
PARTITION BY RANGE (stat_date)
( PARTITION dws_sales_day_store_category_p2022_01 VALUES LESS THAN ('2022-02-01'),
  PARTITION dws_sales_day_store_category_pmax     VALUES LESS THAN (MAXVALUE) );
CREATE INDEX IF NOT EXISTS idx_dws_scat_store
    ON dw.dws_sales_day_store_category (store_id) LOCAL;

CREATE TABLE IF NOT EXISTS dw.dws_sales_day_store_staff (
    stat_date    date          NOT NULL,
    store_id     integer       NOT NULL,
    store_status varchar(16),
    staff_id     integer,
    pay_cnt      bigint        NOT NULL,
    amount       numeric(18,2) NOT NULL,
    dq_flag      boolean       NOT NULL,
    run_id       varchar(64)   NOT NULL,
    built_at     timestamp with time zone NOT NULL DEFAULT now()
) WITH (ORIENTATION = COLUMN, COMPRESSION = HIGH)
PARTITION BY RANGE (stat_date)
( PARTITION dws_sales_day_store_staff_p2022_01 VALUES LESS THAN ('2022-02-01'),
  PARTITION dws_sales_day_store_staff_pmax     VALUES LESS THAN (MAXVALUE) );

CREATE TABLE IF NOT EXISTS dw.dws_rental_day_store (
    stat_date     date        NOT NULL,
    store_id      integer     NOT NULL,
    store_status  varchar(16),
    rental_cnt    bigint      NOT NULL,
    returned_cnt  bigint      NOT NULL,
    open_cnt      bigint      NOT NULL,
    overdue_cnt   bigint      NOT NULL,
    max_overdue_d integer,
    dq_flag       boolean     NOT NULL,
    run_id        varchar(64) NOT NULL,
    built_at      timestamp with time zone NOT NULL DEFAULT now()
) WITH (ORIENTATION = COLUMN, COMPRESSION = HIGH)
PARTITION BY RANGE (stat_date)
( PARTITION dws_rental_day_store_p2022_01 VALUES LESS THAN ('2022-02-01'),
  PARTITION dws_rental_day_store_pmax     VALUES LESS THAN (MAXVALUE) );

-- is_complete_period 是 C3 环比/同比正确性的关键开关：口径文档 §3 要求
-- 不完整期间的环比一律返回 NULL。实测若不加此标记，首月不完整会产出
-- +228.46% 的假暴增（2022-02 相对 2022-01）。
CREATE TABLE IF NOT EXISTS dw.dws_sales_month_store (
    stat_month         date          NOT NULL,
    store_id           integer       NOT NULL,
    store_status       varchar(16),
    pay_cnt            bigint        NOT NULL,
    amount             numeric(18,2) NOT NULL,
    customer_cnt       bigint        NOT NULL,
    is_complete_period boolean       NOT NULL,
    dq_flag            boolean       NOT NULL,
    run_id             varchar(64)   NOT NULL,
    built_at           timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT dws_sales_month_store_pk PRIMARY KEY (stat_month, store_id)
) WITH (STORAGE_TYPE = USTORE);

SELECT 'dws tables' AS component,
       CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/4)' END AS result,
       string_agg(tablename, ', ' ORDER BY tablename) AS detail
FROM pg_tables
WHERE schemaname = 'dw' AND tablename LIKE 'dws_%';
