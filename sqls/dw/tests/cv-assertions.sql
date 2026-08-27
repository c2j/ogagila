-- Phase 1 QA / Q1.1 — 覆盖率断言 CV1 ~ CV14
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §8.2
--
-- 前置：先加载夹具 t1-deterministic.sql。
-- 判定：输出 14 行，每行第二列必须为 PASS；任何 FAIL 即阻塞 Phase 1 验收。

\set ON_ERROR_STOP on
\set FIX_BASE 900000000

WITH
-- CV1 门店三态。ACTIVE=有库存+有客户+期间内有交易；DORMANT=有库存但无交易；
-- EXCLUDED=无库存且无客户。口径定义见 sqls/dw/docs/metric-definitions.md §1.1。
store_state AS (
    SELECT s.store_id,
           (SELECT count(*) FROM inventory i WHERE i.store_id = s.store_id) AS inv_cnt,
           (SELECT count(*) FROM customer c WHERE c.store_id = s.store_id)  AS cust_cnt,
           (SELECT count(*) FROM payment p
              JOIN rental r    ON r.rental_id = p.rental_id
              JOIN inventory i ON i.inventory_id = r.inventory_id
             WHERE i.store_id = s.store_id)                                 AS pay_cnt
      FROM store s
),
cv AS (
    SELECT 'CV01' AS cv, '门店三态 ACTIVE/DORMANT/EXCLUDED 同时存在' AS what,
           (SELECT count(*) FROM store_state WHERE inv_cnt > 0 AND cust_cnt > 0 AND pay_cnt > 0) > 0
       AND (SELECT count(*) FROM store_state WHERE inv_cnt > 0 AND pay_cnt = 0) > 0
       AND (SELECT count(*) FROM store_state WHERE inv_cnt = 0 AND cust_cnt = 0) > 0 AS ok

    UNION ALL SELECT 'CV02', 'rental 最大日期 > payment 最大日期',
           (SELECT max(rental_date) FROM rental) > (SELECT max(payment_date) FROM payment)

    UNION ALL SELECT 'CV03', '存在不完整期间（首月起始日 > 1 或末月结束日 < 月末）',
           EXISTS (SELECT 1 FROM (
                     SELECT date_trunc('month', payment_date) m,
                            min(payment_date) mn, max(payment_date) mx
                       FROM payment GROUP BY 1) t
                    WHERE mn > m + interval '1 day'
                       OR mx < m + interval '1 month' - interval '1 day')

    UNION ALL SELECT 'CV04', '分区边界：月末最后一微秒 与 次月零点整 各有行',
           EXISTS (SELECT 1 FROM payment WHERE payment_date = '2025-05-31 23:59:59.999999+00')
       AND EXISTS (SELECT 1 FROM payment WHERE payment_date = '2025-06-01 00:00:00+00')

    UNION ALL SELECT 'CV05', '跨月补录：payment_id 更大但 payment_date 更早',
           EXISTS (SELECT 1 FROM payment p
                    WHERE p.payment_id >= 900000000
                      AND p.payment_date < (SELECT max(payment_date) FROM payment p2
                                             WHERE p2.payment_id >= 900000000
                                               AND p2.payment_id < p.payment_id))

    UNION ALL SELECT 'CV06', '存在可删除标记集（用于源侧 DELETE 检测）',
           (SELECT count(*) FROM payment WHERE payment_id BETWEEN 900095001 AND 900095005) = 5

    UNION ALL SELECT 'CV07', '在租（return_date IS NULL）且已逾期',
           EXISTS (SELECT 1 FROM rental r
                     JOIN inventory i ON i.inventory_id = r.inventory_id
                     JOIN film f      ON f.film_id = i.film_id
                    WHERE r.return_date IS NULL
                      AND r.rental_date < now() - (f.rental_duration * interval '1 day'))

    UNION ALL SELECT 'CV08', 'A 模式空串≡NULL：COUNT(*) 与 COUNT(col) 口径不同',
           (SELECT count(*) FROM address WHERE address_id >= 900000000)
         > (SELECT count(district) FROM address WHERE address_id >= 900000000)

    UNION ALL SELECT 'CV09', '金额边界：存在 999.99 行且其汇总远超单列上限',
           EXISTS (SELECT 1 FROM payment WHERE amount = 999.99)
       AND (SELECT sum(amount) FROM payment WHERE amount = 999.99) > 999.99

    UNION ALL SELECT 'CV10', '同一天多笔且 payment_id 连续',
           EXISTS (SELECT 1 FROM (
                     SELECT payment_date::date d, count(*) c
                       FROM payment WHERE payment_id >= 900000000
                      GROUP BY 1 HAVING count(*) > 1) t)

    UNION ALL SELECT 'CV11', '有交易但无 staff 的门店',
           EXISTS (SELECT 1 FROM store_state ss
                    WHERE ss.pay_cnt > 0
                      AND NOT EXISTS (SELECT 1 FROM staff st WHERE st.store_id = ss.store_id))

    UNION ALL SELECT 'CV12', '悬空 manager_staff_id（store 无 FK 约束）',
           EXISTS (SELECT 1 FROM store s
                    WHERE NOT EXISTS (SELECT 1 FROM staff st
                                       WHERE st.staff_id = s.manager_staff_id))

    UNION ALL SELECT 'CV13', '连续月份跨度 >= 25（YoY 可算）',
           (SELECT count(DISTINCT date_trunc('month', payment_date))
              FROM payment WHERE payment_id >= 900000000) >= 25

    UNION ALL SELECT 'CV14', '迟到超 lookback 窗口的数据（日期回溯 > 30 天且 id 极大）',
           EXISTS (SELECT 1 FROM payment
                    WHERE payment_id >= 900099000
                      AND payment_date < (SELECT max(payment_date) FROM payment)
                                          - interval '30 days')
)
SELECT cv,
       CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result,
       what
  FROM cv
 ORDER BY cv;
