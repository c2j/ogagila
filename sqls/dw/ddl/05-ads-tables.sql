-- Phase 2 — C1 门店大屏
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §4.3 / §5.4
-- 口径依据：sqls/dw/docs/metric-definitions.md §1 §4
--
-- C1 是四类消费者中唯一物理化的非披露层，原因是延迟敏感（准实时 30s~5min）。
--
-- 为什么不用物化视图：实测 `REFRESH MATERIALIZED VIEW ... CONCURRENTLY` 语法
-- 不支持，普通 REFRESH 持排他锁会阻塞大屏读取。故用"小表 + 可选影子表切换"。
--
-- 行存 + zstd 压缩：大屏表是点查/小范围扫描对象（按 store_id 取当日一行），
-- 列存在此无收益且不支持我们需要的 hll 列。

\set ON_ERROR_STOP on

-- uv_hll 用 HyperLogLog 存当日去重客户的近似基数（Gauss 特性采用清单第 12 项）。
-- 实测精度：1 万基数下近似值 10043，误差 0.43%，对大屏足够；
-- 精确去重需扫全量明细，不适合准实时刷新。
-- exact_customer_cnt 同时保留，便于对账与精度回归。
CREATE TABLE IF NOT EXISTS dw.ads_screen_store_today (
    stat_date          date          NOT NULL,
    store_id           integer       NOT NULL,
    store_name         text,
    store_city         text,
    pay_cnt            bigint        NOT NULL,
    amount             numeric(18,2) NOT NULL,
    exact_customer_cnt bigint        NOT NULL,
    uv_hll             hll,
    approx_uv          bigint,
    rental_cnt         bigint        NOT NULL,
    open_cnt           bigint        NOT NULL,
    overdue_cnt        bigint        NOT NULL,
    top_category       text,
    dq_flag            boolean       NOT NULL,
    run_id             varchar(64)   NOT NULL,
    refreshed_at       timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT ads_screen_store_today_pk PRIMARY KEY (stat_date, store_id)
) WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);

SELECT 'c1 table' AS component,
       CASE WHEN count(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS result
FROM pg_tables WHERE schemaname = 'dw' AND tablename = 'ads_screen_store_today';
