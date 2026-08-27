-- Phase 1 — DWD 明细层
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §4.2 / DD2 / DD3 / DD4
-- 口径依据：sqls/dw/docs/metric-definitions.md §1 §2 §5 §7
--
-- 存储形态（Gauss 特性采用清单第 1/2/4 项）：
--   列存 ORIENTATION=COLUMN + COMPRESSION=HIGH + RANGE 月分区
--   实测已确认：分区裁剪生效且计划走向量化算子
--   （Row Adapter / Vector Aggregate / Vector Partition Iterator / Partitioned CStore Scan）
--
-- 实测约束（决定了以下三处设计）：
--   1) 列存表不支持 SPLIT PARTITION
--      （Un-support feature / column-store relation doesn't support this ALTER yet）。
--      但本层仍建 MAXVALUE 兜底分区，因为无兜底分区时不仅超界**插入**报错，
--      谓词完全超界的**查询**也会报 "Fail to find partition from sequence."。
--      新增月分区由 PKG_ETL_CORE.ensure_partitions 走路径 C：
--      DROP pmax -> ADD 月分区 -> 重建 pmax（要求 pmax 为空，由 DQ 规则
--      PARTITION_OVERFLOW 保证）。
--   2) 列存表不支持 UNIQUE 索引（psort access method 限制）->
--      方案 §5.3 的"防御性护栏 UNIQUE(stat_date, 维度键)"在本层无法落地，
--      改由 DQ 规则 DWD_DUPLICATE_KEY 承担重复检测。
--   3) 列存表不支持外键与 CHECK 约束 -> 维度一致性、stat_date 整日性
--      同样依赖 DQ 规则（DWD_DUPLICATE_KEY / STAT_DATE_NOT_TRUNCATED）
--      而非物理约束。
--
-- 维度退化（DD3）：store/category/city/country 冗余进事实表，避免 1 亿行级
-- 事实表与维表的大 join。这也顺带规避了约束 3（本来就无法建 FK）。

\set ON_ERROR_STOP on

-- 金额列一律 numeric(18,2)：源列 payment.amount 是 numeric(5,2)（上限 999.99），
-- 而实测单月汇总已达 11413.86、造数用例的 999.99 分组汇总达 9999.90。
-- 风险不在聚合（sum 会自动提升为无约束 numeric），而在**汇总表 DDL 照抄源列类型**。
CREATE TABLE IF NOT EXISTS dw.dwd_fact_payment (
    stat_date        date          NOT NULL,
    payment_ts       timestamp with time zone NOT NULL,
    payment_id       integer       NOT NULL,
    rental_id        integer,
    customer_id      integer,
    staff_id         integer,
    store_id         integer,
    store_status     varchar(16),
    film_id          integer,
    category_id      integer,
    category_name    text,
    store_city       text,
    store_country    text,
    amount           numeric(18,2) NOT NULL,
    is_within_cutoff boolean       NOT NULL,
    multi_category   boolean,
    dq_flag          boolean       NOT NULL,
    run_id           varchar(64)   NOT NULL,
    built_at         timestamp with time zone NOT NULL DEFAULT now()
) WITH (ORIENTATION = COLUMN, COMPRESSION = HIGH)
PARTITION BY RANGE (stat_date)
( PARTITION dwd_fact_payment_p2022_01 VALUES LESS THAN ('2022-02-01'),
  PARTITION dwd_fact_payment_pmax     VALUES LESS THAN (MAXVALUE) );

CREATE INDEX IF NOT EXISTS idx_dwd_pay_store ON dw.dwd_fact_payment (store_id) LOCAL;
CREATE INDEX IF NOT EXISTS idx_dwd_pay_cat   ON dw.dwd_fact_payment (category_id) LOCAL;

CREATE TABLE IF NOT EXISTS dw.dwd_fact_rental (
    stat_date        date          NOT NULL,
    rental_ts        timestamp with time zone NOT NULL,
    rental_id        integer       NOT NULL,
    return_ts        timestamp with time zone,
    customer_id      integer,
    staff_id         integer,
    inventory_id     integer,
    film_id          integer,
    store_id         integer,
    store_status     varchar(16),
    category_id      integer,
    category_name    text,
    rental_duration  smallint,
    is_returned      boolean       NOT NULL,
    is_overdue       boolean       NOT NULL,
    overdue_days     integer,
    is_within_cutoff boolean       NOT NULL,
    dq_flag          boolean       NOT NULL,
    run_id           varchar(64)   NOT NULL,
    built_at         timestamp with time zone NOT NULL DEFAULT now()
) WITH (ORIENTATION = COLUMN, COMPRESSION = HIGH)
PARTITION BY RANGE (stat_date)
( PARTITION dwd_fact_rental_p2022_01 VALUES LESS THAN ('2022-02-01'),
  PARTITION dwd_fact_rental_pmax     VALUES LESS THAN (MAXVALUE) );

CREATE INDEX IF NOT EXISTS idx_dwd_rent_store ON dw.dwd_fact_rental (store_id) LOCAL;

SELECT 'dwd tables' AS component,
       CASE WHEN count(*) = 2 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/2)' END AS result,
       string_agg(relname || '=' || (SELECT count(*) FROM pg_partition pp
                                     WHERE pp.parentid = c.oid AND pp.parttype = 'p')::text,
                  ', ' ORDER BY relname) AS partitions
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'dw' AND c.relname IN ('dwd_fact_payment','dwd_fact_rental');
