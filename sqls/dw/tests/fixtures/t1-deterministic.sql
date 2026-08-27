-- Phase 1 / T1 — 确定性造数夹具
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §8.1(T1) / §8.2(CV1~CV14)
--
-- 设计原则（与 SDV 的分工见方案 §8.1）：
--   1) 完全确定性，不使用 random()/setseed —— 金额与行数由公式给出，
--      故期望值可解析计算，能写精确断言。这是 T1 存在的理由：
--      SDV 产出的值不可预知，无法做 ground-truth 断言。
--   2) 保留 ID 区间 >= 900000000 —— 清理即 DELETE WHERE id >= 900000000，
--      不触碰基础 Pagila 数据，也不推进源序列。
--
-- 期望值（供断言使用，勿改公式）：
--   月份跨度      : 2024-01 ~ 2026-08 = 32 个月（满足 CV13 的 YoY >= 25 月要求）
--   每月常规笔数  : 50
--   每月常规金额  : 275.00   = sum(1.00 + (n % 10)) for n in 1..50
--   常规总笔数    : 1600     = 32 * 50
--   常规总金额    : 8800.00  = 32 * 275.00
--   边界用例另计（见文件末尾 CV 明细），不计入上述常规值。
--
-- 用法：
--   加载  docker exec pagila gsql-pagila -f /dw-tests/fixtures/t1-deterministic.sql
--   清理  docker exec pagila gsql-pagila -f /dw-tests/fixtures/t1-cleanup.sql

\set ON_ERROR_STOP on
\set FIX_BASE 900000000

BEGIN;

DELETE FROM payment WHERE payment_id >= :FIX_BASE;
DELETE FROM rental  WHERE rental_id  >= :FIX_BASE;
DELETE FROM inventory WHERE inventory_id >= :FIX_BASE;
DELETE FROM staff   WHERE staff_id   >= :FIX_BASE;
DELETE FROM customer WHERE customer_id >= :FIX_BASE;
DELETE FROM store   WHERE store_id   >= :FIX_BASE;
DELETE FROM address WHERE address_id  >= :FIX_BASE;

-- 夹具地址：CV8 需要 phone/district 的 ''、NULL、正常值三种形态。
-- A 兼容模式下 '' 与 NULL 等价，此处刻意同时写入以验证 COUNT 口径差异。
INSERT INTO address(address_id, address, address2, district, city_id, postal_code, phone) VALUES
    (:FIX_BASE + 1, 'FIXTURE ADDR ACTIVE',   NULL, 'D-NORMAL', 1, '11111', '13800000001'),
    (:FIX_BASE + 2, 'FIXTURE ADDR DORMANT',  NULL, NULL,       1, '22222', NULL),
    (:FIX_BASE + 3, 'FIXTURE ADDR EXCLUDED', NULL, '',         1, '33333', ''),
    (:FIX_BASE + 4, 'FIXTURE ADDR ORPHANMGR',NULL, 'D-NORMAL', 1, '44444', '13800000004');

-- 夹具门店，对应 CV1 三态 + CV11 有交易无员工 + CV12 悬空 manager_staff_id。
-- store.manager_staff_id 无 FK 约束（源库缺陷 D5），故 CV12 可直接写不存在的值。
INSERT INTO store(store_id, manager_staff_id, address_id) VALUES
    (:FIX_BASE + 1, :FIX_BASE + 1, :FIX_BASE + 1),
    (:FIX_BASE + 2, :FIX_BASE + 2, :FIX_BASE + 2),
    (:FIX_BASE + 3, :FIX_BASE + 3, :FIX_BASE + 3),
    (:FIX_BASE + 4, 987654321,     :FIX_BASE + 4);

INSERT INTO staff(staff_id, first_name, last_name, address_id, email, store_id, active, username) VALUES
    (:FIX_BASE + 1, 'Fix', 'ActiveMgr',  :FIX_BASE + 1, 'fix1@example.com', :FIX_BASE + 1, true, 'fix_active'),
    (:FIX_BASE + 2, 'Fix', 'DormantMgr', :FIX_BASE + 2, 'fix2@example.com', :FIX_BASE + 2, true, 'fix_dormant'),
    (:FIX_BASE + 3, 'Fix', 'ExclMgr',    :FIX_BASE + 3, 'fix3@example.com', :FIX_BASE + 3, true, 'fix_excluded');

INSERT INTO customer(customer_id, store_id, first_name, last_name, email, address_id, activebool, create_date, active) VALUES
    (:FIX_BASE + 1, :FIX_BASE + 1, 'Fix', 'CustActive',  'c1@example.com', :FIX_BASE + 1, true,  '2024-01-01', 1),
    (:FIX_BASE + 2, :FIX_BASE + 2, 'Fix', 'CustDormant', 'c2@example.com', :FIX_BASE + 2, true,  '2024-01-01', 1),
    (:FIX_BASE + 4, :FIX_BASE + 4, 'Fix', 'CustOrphan',  'c4@example.com', :FIX_BASE + 4, false, '2024-01-01', 0);

-- ACTIVE 店有库存有客户有交易；DORMANT 店有库存有客户但全程无 payment；
-- EXCLUDED 店（FIX_BASE+3）刻意不建 inventory 也不建 customer。
INSERT INTO inventory(inventory_id, film_id, store_id)
SELECT :FIX_BASE + n, 1 + (n % 10), :FIX_BASE + 1 FROM generate_series(1, 20) AS n;
INSERT INTO inventory(inventory_id, film_id, store_id)
SELECT :FIX_BASE + 100 + n, 1 + (n % 10), :FIX_BASE + 2 FROM generate_series(1, 20) AS n;
INSERT INTO inventory(inventory_id, film_id, store_id)
SELECT :FIX_BASE + 200 + n, 1 + (n % 10), :FIX_BASE + 4 FROM generate_series(1, 5) AS n;

-- 常规月度交易：32 个月 × 50 笔。
-- payment_date 用 ((n-1) % 28) 天偏移保证不跨月；金额 1.00 + (n % 10) 使每月
-- 合计恒为 275.00（可解析验证）。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, return_date, staff_id)
SELECT :FIX_BASE + 1000 + (m.idx * 100) + n,
       m.month_start + ((n - 1) % 28) * interval '1 day' + interval '10 hours',
       :FIX_BASE + 1 + (n % 20),
       :FIX_BASE + 1,
       CASE WHEN n % 10 = 0 THEN NULL
            ELSE m.month_start + ((n - 1) % 28) * interval '1 day' + interval '3 days' END,
       :FIX_BASE + 1
FROM (SELECT row_number() OVER (ORDER BY g) - 1 AS idx, g AS month_start
      FROM generate_series(timestamptz '2024-01-01 00:00:00+00',
                           timestamptz '2026-08-01 00:00:00+00',
                           interval '1 month') AS g) m
CROSS JOIN generate_series(1, 50) AS n;

INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date)
SELECT :FIX_BASE + 1000 + (m.idx * 100) + n,
       :FIX_BASE + 1,
       :FIX_BASE + 1,
       :FIX_BASE + 1000 + (m.idx * 100) + n,
       (1.00 + (n % 10))::numeric(5,2),
       m.month_start + ((n - 1) % 28) * interval '1 day' + interval '12 hours'
FROM (SELECT row_number() OVER (ORDER BY g) - 1 AS idx, g AS month_start
      FROM generate_series(timestamptz '2024-01-01 00:00:00+00',
                           timestamptz '2026-08-01 00:00:00+00',
                           interval '1 month') AS g) m
CROSS JOIN generate_series(1, 50) AS n;

-- DORMANT 店：有库存有客户，但只有 rental 没有 payment。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, return_date, staff_id)
SELECT :FIX_BASE + 500 + n,
       timestamptz '2024-03-01 00:00:00+00' + n * interval '1 day',
       :FIX_BASE + 100 + n, :FIX_BASE + 2, NULL, :FIX_BASE + 2
FROM generate_series(1, 5) AS n;

-- CV4 分区边界：月末最后一微秒 与 次月零点整（UTC）。
-- 用于验证半开区间 [from, to) 的归属与分区裁剪不串月。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, staff_id) VALUES
    (:FIX_BASE + 90001, '2025-05-31 23:59:59.999999+00', :FIX_BASE + 1, :FIX_BASE + 1, :FIX_BASE + 1),
    (:FIX_BASE + 90002, '2025-06-01 00:00:00+00',        :FIX_BASE + 2, :FIX_BASE + 1, :FIX_BASE + 1);
INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date) VALUES
    (:FIX_BASE + 90001, :FIX_BASE + 1, :FIX_BASE + 1, :FIX_BASE + 90001, 11.11, '2025-05-31 23:59:59.999999+00'),
    (:FIX_BASE + 90002, :FIX_BASE + 1, :FIX_BASE + 1, :FIX_BASE + 90002, 22.22, '2025-06-01 00:00:00+00');

-- CV5 回溯窗口内补录：payment_id 最大但 payment_date 落在上月。
-- 只用 payment_id 做水位线会漏掉这类行 → 验证 ID+TS 双轨的必要性。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, staff_id) VALUES
    (:FIX_BASE + 90003, '2026-07-10 10:00:00+00', :FIX_BASE + 3, :FIX_BASE + 1, :FIX_BASE + 1);
INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date) VALUES
    (:FIX_BASE + 99999, :FIX_BASE + 1, :FIX_BASE + 1, :FIX_BASE + 90003, 33.33, '2026-07-10 10:00:00+00');

-- CV14 超出 lookback 的迟到数据：id 极大但日期回溯到 2024 年，
-- 只能靠月度全量对账兜住（方案 §6.3/§6.4）。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, staff_id) VALUES
    (:FIX_BASE + 90004, '2024-02-05 10:00:00+00', :FIX_BASE + 4, :FIX_BASE + 1, :FIX_BASE + 1);
INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date) VALUES
    (:FIX_BASE + 99998, :FIX_BASE + 1, :FIX_BASE + 1, :FIX_BASE + 90004, 44.44, '2024-02-05 10:00:00+00');

-- CV9 金额上界：payment.amount 是 numeric(5,2)，999.99 是可存的最大值。
-- 多行 999.99 使汇总远超单列上限，用于验证汇总表必须用 numeric(18,2)。
-- 注意：rental 上有唯一约束 (rental_date, inventory_id, customer_id)，
-- 故以下所有多行块都必须让时间或库存随 n 变化。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, staff_id)
SELECT :FIX_BASE + 91000 + n,
       timestamptz '2025-09-15 10:00:00+00' + n * interval '1 minute',
       :FIX_BASE + 1 + (n % 20), :FIX_BASE + 1, :FIX_BASE + 1
FROM generate_series(1, 10) AS n;
INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date)
SELECT :FIX_BASE + 91000 + n, :FIX_BASE + 1, :FIX_BASE + 1, :FIX_BASE + 91000 + n,
       999.99, timestamptz '2025-09-15 10:00:00+00' + n * interval '1 minute'
FROM generate_series(1, 10) AS n;

-- CV10 同日并发：同一天多笔、payment_id 连续，验证水位线安全边界。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, staff_id)
SELECT :FIX_BASE + 92000 + n,
       timestamptz '2026-06-20 08:00:00+00' + n * interval '1 minute',
       :FIX_BASE + 1 + (n % 20), :FIX_BASE + 1, :FIX_BASE + 1
FROM generate_series(1, 5) AS n;
INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date)
SELECT :FIX_BASE + 92000 + n, :FIX_BASE + 1, :FIX_BASE + 1, :FIX_BASE + 92000 + n,
       5.00, timestamptz '2026-06-20 08:00:00+00' + n * interval '1 second'
FROM generate_series(1, 5) AS n;

-- CV7 逾期在租：return_date IS NULL 且租期已远超 film.rental_duration。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, return_date, staff_id)
SELECT :FIX_BASE + 93000 + n,
       timestamptz '2025-01-10 10:00:00+00' + n * interval '1 minute',
       :FIX_BASE + 1 + (n % 20), :FIX_BASE + 1, NULL, :FIX_BASE + 1
FROM generate_series(1, 3) AS n;

-- CV2 rental 日期超出 payment 日期上界：造一批只有 rental 没有 payment 的未来行。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, return_date, staff_id)
SELECT :FIX_BASE + 94000 + n,
       timestamptz '2026-09-05 10:00:00+00' + n * interval '1 minute',
       :FIX_BASE + 1 + (n % 20), :FIX_BASE + 1, NULL, :FIX_BASE + 1
FROM generate_series(1, 3) AS n;

-- CV6 可删除标记集：供"源侧 DELETE 检测"用例删除后验证对账能发现差异。
INSERT INTO rental(rental_id, rental_date, inventory_id, customer_id, return_date, staff_id)
SELECT :FIX_BASE + 95000 + n,
       timestamptz '2025-11-11 10:00:00+00' + n * interval '1 minute',
       :FIX_BASE + 1 + (n % 20), :FIX_BASE + 1,
       timestamptz '2025-11-14 10:00:00+00', :FIX_BASE + 1
FROM generate_series(1, 5) AS n;
INSERT INTO payment(payment_id, customer_id, staff_id, rental_id, amount, payment_date)
SELECT :FIX_BASE + 95000 + n, :FIX_BASE + 1, :FIX_BASE + 1, :FIX_BASE + 95000 + n,
       7.77, timestamptz '2025-11-11 10:00:00+00' + n * interval '1 minute'
FROM generate_series(1, 5) AS n;

COMMIT;

-- 造数会写入 9e8 段的显式 id，远高于源序列当前值。若此时水位线已推进过，
-- ID 轨会被永久抬高到 9e8，之后走序列的正常插入（id 小得多）将被静默跳过
-- （详见 PKG_ETL_CORE.plan_increment 的实测隐患说明）。故加载夹具后必须重置。
UPDATE dw.etl_watermark
   SET wm_id_value = NULL, wm_ts_value = NULL, last_run_id = NULL, updated_at = now()
 WHERE source_name IN ('payment', 'rental');

SELECT 'fixture loaded' AS status,
       (SELECT count(*) FROM payment WHERE payment_id >= 900000000) AS payments,
       (SELECT count(*) FROM rental  WHERE rental_id  >= 900000000) AS rentals,
       (SELECT count(DISTINCT date_trunc('month', payment_date))
          FROM payment WHERE payment_id >= 900000000) AS distinct_months,
       (SELECT count(*) FROM dw.etl_watermark
         WHERE source_name IN ('payment','rental') AND wm_id_value IS NULL) AS wm_reset;
