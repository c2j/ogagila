-- Phase 0 / F1+F2 — 源库止血修复
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §6.1
-- 幂等：可重复执行。

\set ON_ERROR_STOP on

-- F1: payment 原有 7 个月分区上界止于 2022-08-01(UTC) 且无兜底分区，
-- 任何 payment_date >= 2022-08-01 的插入会报 "inserted partition key does not
-- map to any table partition" —— 写入可用性事故，故加 MAXVALUE 兜底。
--
-- 实测确认的两条反直觉约束（后续维护必读）：
--   1) ADD PARTITION 不接受 UPDATE GLOBAL INDEX 子句（ADD 不移动数据）
--   2) 存在 MAXVALUE 分区后，新增月分区不能再用 ADD PARTITION，会报
--      "upper boundary of adding partition MUST overtop last existing partition"，
--      必须改用 SPLIT PARTITION —— 见 PKG_ETL_CORE.ensure_partitions
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_partition
               WHERE parentid = 'public.payment'::regclass
                 AND parttype = 'p' AND relname = 'payment_pmax') THEN
        RAISE NOTICE 'F1 skipped: payment_pmax already exists';
    ELSE
        ALTER TABLE public.payment ADD PARTITION payment_pmax VALUES LESS THAN (MAXVALUE);
        RAISE NOTICE 'F1 done: payment_pmax created';
    END IF;
END $$;

-- F2: 以下 4 列均已有 FK 约束但无支撑索引。实测证据：JOIN 键选错曾导致
-- 445K 中间结果膨胀（336ms）。payment 是分区表，索引建在父表上（openGauss
-- 内联分区惯例，与 sqls/ddl/schema.sql 现有 idx_fk_payment_* 一致）。
CREATE INDEX IF NOT EXISTS idx_fk_payment_rental_id
    ON public.payment USING btree (rental_id) LOCAL;

CREATE INDEX IF NOT EXISTS idx_fk_rental_customer_id
    ON public.rental USING btree (customer_id);

CREATE INDEX IF NOT EXISTS idx_fk_rental_staff_id
    ON public.rental USING btree (staff_id);

CREATE INDEX IF NOT EXISTS idx_fk_film_category_category_id
    ON public.film_category USING btree (category_id);

SELECT 'F1' AS fix,
       CASE WHEN EXISTS (SELECT 1 FROM pg_partition
                         WHERE parentid='public.payment'::regclass
                           AND parttype='p' AND relname='payment_pmax')
            THEN 'PASS' ELSE 'FAIL' END AS result,
       'payment_pmax 兜底分区' AS detail
UNION ALL
SELECT 'F2', CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/4)' END,
       '4 个 FK 缺失索引'
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN ('idx_fk_payment_rental_id',
                    'idx_fk_rental_customer_id',
                    'idx_fk_rental_staff_id',
                    'idx_fk_film_category_category_id');
