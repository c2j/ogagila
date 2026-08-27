-- Phase 4 / T3 — 规模造数（性能压测用）
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §8.1(T3) / §9 Phase 4
--
-- 与 T1 的分工（§8.1）：
--   T1 确定性夹具 -> 功能正确性断言（值可预期，规模千~万行）
--   T3 规模造数   -> 性能压测（规模千万~亿行，值不需可预期）
--   SDV           -> 分布真实性（Phase 3，单表 GaussianCopula）
--
-- ID 区间：T3 使用 1e9 ~ 1.999e9，与 T1 的 9e8 段互不重叠，可独立清理。
-- payment_id 是 integer，上限 2147483647，故单次最多约 10 亿行。
--
-- 用法：由 t3-scale.sh 驱动（提供参数默认值）。
--   bash t3-scale.sh --rentals 200000 --payments 1000000 --months 12
-- 直接运行本 SQL 时三个变量必须由 -v 显式给出 —— gsql **不支持 \if**，
-- 因此无法在 SQL 内部实现"未设置则取默认值"。
--
-- ⚠️ 造数完成后必须重置水位线（脚本末尾已做）：T3 写入 1e9 段显式 id 会把 ID
-- 水位线抬高，导致后续走序列的正常插入被静默跳过（隐患 G29）。

\set ON_ERROR_STOP on
\set T3_BASE 1000000000

\echo '=== T3 参数 ==='
SELECT :n_rental AS n_rental, :n_payment AS n_payment, :months AS months_span;

\timing on

\echo '=== 清理上一次 T3 数据 ==='
DELETE FROM payment WHERE payment_id >= :T3_BASE AND payment_id < 2000000000;
DELETE FROM rental  WHERE rental_id  >= :T3_BASE AND rental_id  < 2000000000;

\echo '=== 确保源表分区覆盖目标区间 ==='
CALL dw.pkg_etl_core.ensure_partitions('payment', 3);

\echo '=== 生成 rental（rental_date 按秒递增保证唯一索引不冲突）==='
-- 日期必须**线性铺开**到目标跨度，不能写成 n % 跨度秒数：当行数小于跨度秒数时
-- 取模等价于恒等映射，所有行会挤在前 N 秒内（实测 months=6 时 t3_months=1）。
-- 这里用 n * 跨度 / 行数 把 n 均匀映射到 [0, 跨度)。
--
-- rental 上有 UNIQUE(rental_date, inventory_id, customer_id)：铺开后每个 n 落在
-- 不同秒（行数 << 跨度秒数），加上 inventory/customer 也随 n 变化，唯一性成立。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, return_date, staff_id)
SELECT :T3_BASE + n,
       timestamptz '2024-01-01 00:00:00+00'
         + ((n::bigint * (:months * 2592000)) / :n_rental) * interval '1 second',
       (SELECT min(inventory_id) FROM inventory) + (n % 4000),
       (SELECT min(customer_id) FROM customer) + (n % 500),
       CASE WHEN n % 10 = 0 THEN NULL
            ELSE timestamptz '2024-01-01 00:00:00+00'
                 + ((n::bigint * (:months * 2592000)) / :n_rental) * interval '1 second'
                 + interval '3 days' END,
       (SELECT min(staff_id) FROM staff WHERE staff_id > 0) + (n % 2)
FROM generate_series(1, :n_rental) AS n;

\echo '=== 生成 payment（多笔 payment 可共享同一 rental，符合业务语义）==='
-- payment.rental_id 只有 FK 没有唯一约束，故 N 笔 payment 可循环引用
-- M 条 rental（N >> M），既真实又把 rental 的生成量降到 1/5。
INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date)
SELECT :T3_BASE + n,
       (SELECT min(customer_id) FROM customer) + (n % 500),
       (SELECT min(staff_id) FROM staff WHERE staff_id > 0) + (n % 2),
       :T3_BASE + 1 + (n % :n_rental),
       (0.99 + (n % 900) * 0.01)::numeric(5,2),
       timestamptz '2024-01-01 00:00:00+00'
         + ((n::bigint * (:months * 2592000)) / :n_payment) * interval '1 second'
FROM generate_series(1, :n_payment) AS n;

\timing off

\echo '=== 重置水位线（G29：防止 1e9 段 id 污染 ID 轨）==='
UPDATE dw.etl_watermark
   SET wm_id_value = NULL, wm_ts_value = NULL, last_run_id = NULL, updated_at = now()
 WHERE source_name IN ('payment', 'rental');

\echo '=== T3 结果 ==='
SELECT 't3 loaded' AS status,
       (SELECT count(*) FROM payment WHERE payment_id >= 1000000000
                                       AND payment_id < 2000000000) AS t3_payments,
       (SELECT count(*) FROM rental  WHERE rental_id  >= 1000000000
                                       AND rental_id  < 2000000000) AS t3_rentals,
       (SELECT count(*) FROM payment) AS total_payments,
       (SELECT count(DISTINCT date_trunc('month', payment_date))
          FROM payment WHERE payment_id >= 1000000000) AS t3_months;
