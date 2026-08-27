-- Phase 1 / T1 — 夹具清理
-- 依赖保留 ID 区间约定：所有夹具行的主键 >= 900000000。
-- 删除顺序必须由子表到父表，否则触发 FK 约束。

\set ON_ERROR_STOP on
\set FIX_BASE 900000000

BEGIN;
DELETE FROM payment   WHERE payment_id   >= :FIX_BASE;
DELETE FROM rental    WHERE rental_id    >= :FIX_BASE;
DELETE FROM inventory WHERE inventory_id >= :FIX_BASE;
DELETE FROM customer  WHERE customer_id  >= :FIX_BASE;
DELETE FROM staff     WHERE staff_id     >= :FIX_BASE;
DELETE FROM store     WHERE store_id     >= :FIX_BASE;
DELETE FROM address   WHERE address_id   >= :FIX_BASE;
COMMIT;

SELECT 'fixture cleanup' AS status,
       (SELECT count(*) FROM payment   WHERE payment_id   >= 900000000) AS payments,
       (SELECT count(*) FROM rental    WHERE rental_id    >= 900000000) AS rentals,
       (SELECT count(*) FROM store     WHERE store_id     >= 900000000) AS stores,
       (SELECT count(*) FROM address   WHERE address_id   >= 900000000) AS addresses;
