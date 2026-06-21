-- =============================================================================
-- ogexplain-analyzer Ground Truth Query Set v3
-- =============================================================================
-- 目标: 覆盖 ogexplain-analyzer v0.2.x 的全部 25 条诊断规则
-- Schema: c2j/ogagila (openGauss 7.0.0-RC1, Oracle 兼容模式)
-- 数据规模: film=1000, actor=200, customer=599, address=603, rental~16k,
--           payment~16k (按月分 7 区), inventory~4581, category=16
-- 用法: 每条 query 前用 `-- @id: QXX` `-- @target: RULE-ID` 注释标记
--       ground truth 的 root_cause 直接对应 target 字段
-- 注意: 部分 query 触发 EST/STATS/SKEW 需要先 SET 或 DROP STATS,
--       这些 query 在 run_explain.py 里会单独处理
-- =============================================================================

-- =============================================================================
-- [SCAN-001] Large table full scan — 8 queries
-- 触发条件: Seq Scan on table with rows >= configurable threshold(默认 10000)
-- =============================================================================

-- @id: Q01
-- @target: SCAN-001
-- @severity: warning
-- @scenario: rental 表(16044 行)无 WHERE 条件,触发 Seq Scan + 100% selectivity
SELECT * FROM rental LIMIT 10;

-- @id: Q02
-- @target: SCAN-001
-- @severity: warning
-- @scenario: payment 表(16049 行)按 staff_id 过滤但 staff_id 无索引
SELECT * FROM payment WHERE staff_id = 1 LIMIT 10;

-- @id: Q03
-- @target: SCAN-001
-- @severity: warning
-- @scenario: inventory 表全表扫后按 film_id 过滤(无索引)
SELECT inventory_id, film_id, store_id FROM inventory WHERE film_id BETWEEN 100 AND 200;

-- @id: Q04
-- @target: SCAN-001
-- @severity: warning
-- @scenario: rental 与 payment 笛卡尔积前的 payment Seq Scan
SELECT r.rental_id, p.amount FROM rental r, payment p WHERE r.rental_id = p.rental_id LIMIT 5;

-- @id: Q05
-- @target: SCAN-001
-- @severity: warning
-- @scenario: film_actor 联结表全扫(film_id 无单独索引,虽然有联合 PK)
SELECT COUNT(*) FROM film_actor;

-- @id: Q06
-- @target: SCAN-001
-- @severity: warning
-- @scenario: address 表按 district(非索引列)过滤
SELECT * FROM address WHERE district = 'California' LIMIT 10;

-- @id: Q07
-- @target: SCAN-001
-- @severity: warning
-- @scenario: customer 表 active=1 过滤(active 无索引)
SELECT COUNT(*) FROM customer WHERE active = 1;

-- @id: Q08
-- @target: SCAN-001
-- @severity: warning
-- @scenario: payment 表 amount > 10 高 selectivity 过滤(无索引)
SELECT COUNT(*) FROM payment WHERE amount > 10.00;

-- =============================================================================
-- [SCAN-004] Filter without index — 6 queries
-- 触发条件: Seq Scan + Filter + rows estimation ratio 高
-- =============================================================================

-- @id: Q09
-- @target: SCAN-004
-- @severity: warning
-- @scenario: rental.return_date IS NULL(高频谓词,缺索引)
SELECT COUNT(*) FROM rental WHERE return_date IS NULL;

-- @id: Q10
-- @target: SCAN-004
-- @severity: warning
-- @scenario: customer.email 过滤(email 无索引)
SELECT customer_id, first_name, last_name FROM customer WHERE email LIKE '%@example.org' LIMIT 5;

-- @id: Q11
-- @target: SCAN-004
-- @severity: warning
-- @scenario: payment.amount 范围(无索引,导致 Seq Scan + Filter)
SELECT * FROM payment WHERE amount BETWEEN 5.00 AND 8.00 LIMIT 10;

-- @id: Q12
-- @target: SCAN-004
-- @severity: warning
-- @scenario: staff.username 精确匹配(无索引,典型登录场景)
SELECT * FROM staff WHERE username = 'Mike';

-- @id: Q13
-- @target: SCAN-004
-- @severity: warning
-- @scenario: city.city 名精确查(无索引)
SELECT city_id, country_id FROM city WHERE city = 'London';

-- @id: Q14
-- @target: SCAN-004
-- @severity: warning
-- @scenario: film.description 文本扫描
SELECT COUNT(*) FROM film WHERE description LIKE '%Drama%';

-- =============================================================================
-- [JOIN-001] Nested Loop with large dataset — 5 queries
-- =============================================================================

-- @id: Q15
-- @target: JOIN-001
-- @severity: warning
-- @scenario: customer→rental→payment→inventory→film 5 表嵌套循环
--           外表 rental 16044 行,内表 film 缺高效连接索引时可能触发
SELECT c.customer_id, COUNT(*) AS rental_count
FROM customer c
INNER JOIN rental r ON c.customer_id = r.customer_id
INNER JOIN payment p ON r.rental_id = p.rental_id
INNER JOIN inventory i ON r.inventory_id = i.inventory_id
INNER JOIN film f ON i.film_id = f.film_id
GROUP BY c.customer_id
LIMIT 20;

-- @id: Q16
-- @target: JOIN-001
-- @severity: warning
-- @scenario: rental ↔ inventory NL(staff_id 无索引时)
SELECT r.rental_id, i.film_id, i.store_id
FROM rental r
INNER JOIN inventory i ON r.inventory_id = i.inventory_id
WHERE r.staff_id = 1
LIMIT 10;

-- @id: Q17
-- @target: JOIN-001
-- @severity: warning
-- @scenario: 强制 NL 提示(测试 NL 触发)
SELECT /*+ nestloop(r p) */ r.rental_id, p.amount
FROM rental r
INNER JOIN payment p ON r.rental_id = p.rental_id
WHERE r.customer_id BETWEEN 1 AND 10;

-- @id: Q18
-- @target: JOIN-001
-- @severity: warning
-- @scenario: film→film_actor→actor 三表链
SELECT f.title, a.first_name, a.last_name
FROM film f
INNER JOIN film_actor fa ON f.film_id = fa.film_id
INNER JOIN actor a ON fa.actor_id = a.actor_id
WHERE f.rating = 'PG-13'
LIMIT 20;

-- @id: Q19
-- @target: JOIN-001
-- @severity: warning
-- @scenario: 大表 customer→address NL(address_id 无高效索引时)
SELECT c.customer_id, a.address
FROM customer c
INNER JOIN address a ON c.address_id = a.address_id
WHERE c.active = 1
LIMIT 50;

-- =============================================================================
-- [JOIN-002] Hash spill to disk — 4 queries (SET work_mem 低)
-- =============================================================================

-- @id: Q20
-- @target: JOIN-002
-- @severity: warning
-- @scenario: 大表 Hash Join + 低 work_mem 触发 spill
SET work_mem = '64kB';
SELECT r.rental_id, c.first_name, c.last_name
FROM rental r
INNER JOIN customer c ON r.customer_id = c.customer_id
WHERE r.rental_date >= '2022-06-01';
RESET work_mem;

-- @id: Q21
-- @target: JOIN-002
-- @severity: warning
-- @scenario: 三表 Hash Join 链 + 低内存
SET work_mem = '128kB';
SELECT p.payment_id, c.first_name, f.title
FROM payment p
INNER JOIN customer c ON p.customer_id = c.customer_id
INNER JOIN rental r ON p.rental_id = r.rental_id
INNER JOIN inventory i ON r.inventory_id = i.inventory_id
INNER JOIN film f ON i.film_id = f.film_id
WHERE p.amount > 5.00;
RESET work_mem;

-- @id: Q22
-- @target: JOIN-002
-- @severity: warning
-- @scenario: 4 表 Hash Join
SET work_mem = '256kB';
SELECT COUNT(*)
FROM rental r
JOIN payment p ON r.rental_id = p.rental_id
JOIN customer c ON r.customer_id = c.customer_id
JOIN staff s ON r.staff_id = s.staff_id;
RESET work_mem;

-- @id: Q23
-- @target: JOIN-002
-- @severity: warning
-- @scenario: 自连接 rental 触发大 Hash
SET work_mem = '64kB';
SELECT r1.rental_id, r2.rental_id
FROM rental r1
INNER JOIN rental r2 ON r1.customer_id = r2.customer_id
WHERE r1.rental_date < r2.rental_date;
RESET work_mem;

-- =============================================================================
-- [MEM-001] Sort spilled to disk — 4 queries
-- =============================================================================

-- @id: Q24
-- @target: MEM-001
-- @severity: warning
-- @scenario: 大表 ORDER BY 无索引支撑 + 低内存
SET work_mem = '64kB';
SELECT * FROM rental ORDER BY rental_date LIMIT 100;
RESET work_mem;

-- @id: Q25
-- @target: MEM-001
-- @severity: warning
-- @scenario: 大表 ORDER BY amount
SET work_mem = '128kB';
SELECT * FROM payment ORDER BY amount DESC LIMIT 50;
RESET work_mem;

-- @id: Q26
-- @target: MEM-001
-- @severity: warning
-- @scenario: GROUP BY + ORDER BY 组合排序
SET work_mem = '128kB';
SELECT customer_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM payment
GROUP BY customer_id
ORDER BY total DESC
LIMIT 20;
RESET work_mem;

-- @id: Q27
-- @target: MEM-001
-- @severity: warning
-- @scenario: 多列 ORDER BY 触发 external sort
SET work_mem = '64kB';
SELECT rental_date, customer_id, inventory_id
FROM rental
ORDER BY rental_date, customer_id
LIMIT 200;
RESET work_mem;

-- =============================================================================
-- [MEM-004] High peak memory — 3 queries
-- =============================================================================

-- @id: Q28
-- @target: MEM-004
-- @severity: info
-- @scenario: 大表 Hash Join 峰值内存高
SELECT COUNT(*)
FROM rental r
INNER JOIN payment p ON r.customer_id = p.customer_id
INNER JOIN inventory i ON r.inventory_id = i.inventory_id;

-- @id: Q29
-- @target: MEM-004
-- @severity: info
-- @scenario: 全表 HashAggregate 内存峰值
SELECT customer_id, COUNT(*), SUM(amount), AVG(amount)
FROM payment
GROUP BY customer_id;

-- @id: Q30
-- @target: MEM-004
-- @severity: info
-- @scenario: 多表大 Hash Join
SELECT f.title, COUNT(r.rental_id)
FROM film f
JOIN inventory i ON f.film_id = i.film_id
JOIN rental r ON i.inventory_id = r.inventory_id
JOIN payment p ON r.rental_id = p.rental_id
GROUP BY f.title
LIMIT 30;

-- =============================================================================
-- [SORT-003] Duplicate sort — 3 queries
-- =============================================================================

-- @id: Q31
-- @target: SORT-003
-- @severity: warning
-- @scenario: 嵌套 ORDER BY(外层 + 内层各排一次)
SELECT * FROM (
  SELECT * FROM rental ORDER BY rental_date LIMIT 100
) t
ORDER BY customer_id;

-- @id: Q32
-- @target: SORT-003
-- @severity: warning
-- @scenario: UNION + ORDER BY 触发两层 sort
SELECT rental_id, customer_id FROM rental WHERE staff_id = 1
UNION ALL
SELECT rental_id, customer_id FROM rental WHERE staff_id = 2
ORDER BY 1, 2;

-- @id: Q33
-- @target: SORT-003
-- @severity: warning
-- @scenario: DISTINCT + ORDER BY 不同字段
SELECT DISTINCT customer_id, rental_date FROM rental ORDER BY rental_date;

-- =============================================================================
-- [NET-001] Broadcast large table — 3 queries
-- 注: 单节点不直接触发,但 explain 中的 Stream 节点会暴露
-- =============================================================================

-- @id: Q34
-- @target: NET-001
-- @severity: warning
-- @scenario: 强制 Hash Join 大表驱动,explain 应包含 Broadcast/Redistribute
SELECT /*+ hashjoin(r c) */ COUNT(*)
FROM rental r, customer c
WHERE r.customer_id = c.customer_id;

-- @id: Q35
-- @target: NET-001
-- @severity: warning
-- @scenario: payment 与 customer 联接
SELECT COUNT(*)
FROM payment p, customer c
WHERE p.customer_id = c.customer_id;

-- @id: Q36
-- @target: NET-001
-- @severity: warning
-- @scenario: 嵌套子查询触发多次 broadcast
SELECT c.first_name,
       (SELECT COUNT(*) FROM rental r WHERE r.customer_id = c.customer_id) AS cnt
FROM customer c
WHERE c.active = 1
LIMIT 20;

-- =============================================================================
-- [EST-001] Severe row underestimation — 4 queries (需 stale stats)
-- =============================================================================

-- @id: Q37
-- @target: EST-001
-- @severity: warning
-- @scenario: 删 stats 后严重低估 payment 行数
-- 先插入大量数据让 payment 行数膨胀,再 ANALYZE 一次,然后删 stats
-- 在 run_explain.py 里会先执行 SET 准备
DELETE STATISTICS payment;
SELECT COUNT(*) FROM payment WHERE amount > 5.00;

-- @id: Q38
-- @target: EST-001
-- @severity: warning
-- @scenario: 删 stats 后 rental 估算偏差
DELETE STATISTICS rental;
SELECT COUNT(*) FROM rental WHERE return_date IS NULL;

-- @id: Q39
-- @target: EST-001
-- @severity: warning
-- @scenario: 删 stats 后 customer 估算偏差
DELETE STATISTICS customer;
SELECT COUNT(*) FROM customer WHERE active = 1;

-- @id: Q40
-- @target: EST-001
-- @severity: warning
-- @scenario: 删 stats 后 inventory 估算偏差
DELETE STATISTICS inventory;
SELECT COUNT(*) FROM inventory WHERE store_id = 1;

-- =============================================================================
-- [EST-004] Nested Loop from underestimation — 3 queries
-- =============================================================================

-- @id: Q41
-- @target: EST-004
-- @severity: warning
-- @scenario: 删 stats 后误选 NL(应该选 Hash)
DELETE STATISTICS payment;
SELECT /*+ nestloop(p c) */ COUNT(*)
FROM payment p, customer c
WHERE p.customer_id = c.customer_id;

-- @id: Q42
-- @target: EST-004
-- @severity: warning
-- @scenario: 删 stats 后 rental-inventory 选 NL
DELETE STATISTICS rental;
SELECT r.rental_id, i.store_id
FROM rental r, inventory i
WHERE r.inventory_id = i.inventory_id;

-- @id: Q43
-- @target: EST-004
-- @severity: warning
-- @scenario: 删 stats 后 film_actor 误选 NL
DELETE STATISTICS film_actor;
SELECT f.title, a.last_name
FROM film f, film_actor fa, actor a
WHERE f.film_id = fa.film_id AND fa.actor_id = a.actor_id
LIMIT 50;

-- =============================================================================
-- [TYPE-001] Implicit type coercion — 4 queries
-- =============================================================================

-- @id: Q44
-- @target: TYPE-001
-- @severity: critical
-- @scenario: customer_id integer 字段用字符串比较
SELECT * FROM customer WHERE customer_id = '42';

-- @id: Q45
-- @target: TYPE-001
-- @severity: critical
-- @scenario: staff_id 与 '1' 字符串比较
SELECT * FROM staff WHERE staff_id = '1';

-- @id: Q46
-- @target: TYPE-001
-- @severity: critical
-- @scenario: address_id 整数与字符串
SELECT * FROM address WHERE address_id = '5';

-- @id: Q47
-- @target: TYPE-001
-- @severity: warning
-- @scenario: film_id 数字字符串混合比较
SELECT * FROM film WHERE film_id = '999';

-- =============================================================================
-- [TYPE-004] LIKE leading wildcard — 3 queries
-- =============================================================================

-- @id: Q48
-- @target: TYPE-004
-- @severity: warning
-- @scenario: film.title 前导通配符 LIKE
SELECT film_id, title FROM film WHERE title LIKE '%Action%' LIMIT 10;

-- @id: Q49
-- @target: TYPE-004
-- @severity: warning
-- @scenario: actor.last_name 前导通配符
SELECT actor_id, first_name, last_name FROM actor WHERE last_name LIKE '%son%' LIMIT 10;

-- @id: Q50
-- @target: TYPE-004
-- @severity: warning
-- @scenario: customer.email 前导通配符
SELECT customer_id, email FROM customer WHERE email LIKE '%@example.org' LIMIT 10;

-- =============================================================================
-- [PUSH-001] Query not pushed down — 3 queries
-- =============================================================================

-- @id: Q51
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 复杂表达式阻止谓词下推
SELECT * FROM rental
WHERE EXTRACT(YEAR FROM rental_date) = 2022
LIMIT 10;

-- @id: Q52
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 函数包裹索引列,阻止下推
SELECT * FROM film WHERE UPPER(title) = 'ACADEMY DINOSAUR';

-- @id: Q53
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 算术运算阻止下推
SELECT * FROM payment WHERE amount * 2 > 10.00 LIMIT 10;

-- =============================================================================
-- [PUSH-002] Multi-layer streaming — 3 queries
-- =============================================================================

-- @id: Q54
-- @target: PUSH-002
-- @severity: warning
-- @scenario: 复杂查询产生多层 Streaming 节点
SELECT f.title, COUNT(r.rental_id) AS cnt
FROM film f
JOIN inventory i ON f.film_id = i.film_id
JOIN rental r ON i.inventory_id = r.inventory_id
JOIN payment p ON r.rental_id = p.rental_id
WHERE f.rating = 'PG'
GROUP BY f.title
ORDER BY cnt DESC
LIMIT 20;

-- @id: Q55
-- @target: PUSH-002
-- @severity: warning
-- @scenario: 多层联接 + 子查询
SELECT c.customer_id, c.first_name,
       (SELECT COUNT(*) FROM rental r WHERE r.customer_id = c.customer_id) AS rental_cnt,
       (SELECT SUM(amount) FROM payment p WHERE p.customer_id = c.customer_id) AS total_paid
FROM customer c
WHERE c.active = 1
LIMIT 10;

-- @id: Q56
-- @target: PUSH-002
-- @severity: warning
-- @scenario: CTE + 多层联接
WITH cust_stats AS (
  SELECT customer_id, COUNT(*) AS cnt, SUM(amount) AS total
  FROM payment
  GROUP BY customer_id
)
SELECT c.first_name, c.last_name, cs.cnt, cs.total
FROM customer c
JOIN cust_stats cs ON c.customer_id = cs.customer_id
WHERE cs.total > 30
LIMIT 20;

-- =============================================================================
-- [PART-001] Partition pruning failure — 4 queries
-- payment 表按月分 7 区(2022-01 到 2022-07)
-- =============================================================================

-- @id: Q57
-- @target: PART-001
-- @severity: warning
-- @scenario: payment_date 用函数包装,无法分区裁剪
SELECT COUNT(*) FROM payment WHERE EXTRACT(MONTH FROM payment_date) = 3;

-- @id: Q58
-- @target: PART-001
-- @severity: warning
-- @scenario: payment_date IS NULL 不会裁剪
SELECT COUNT(*) FROM payment WHERE payment_date IS NULL;

-- @id: Q59
-- @target: PART-001
-- @severity: warning
-- @scenario: payment_date 用 OR 拆分,部分无法裁剪
SELECT COUNT(*) FROM payment
WHERE payment_date >= '2022-03-01' OR customer_id = 100;

-- @id: Q60
-- @target: PART-001
-- @severity: info
-- @scenario: payment_date 跨全部分区,正确裁剪为全部
SELECT COUNT(*) FROM payment;

-- =============================================================================
-- [SUBQ-001] Correlated subquery not lifted — 3 queries
-- =============================================================================

-- @id: Q61
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: customer 主查询 + 相关 rental 子查询
SELECT c.customer_id, c.first_name,
       (SELECT MAX(rental_date) FROM rental r WHERE r.customer_id = c.customer_id) AS last_rental
FROM customer c
WHERE c.active = 1
LIMIT 20;

-- @id: Q62
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: film 主查询 + 相关 film_actor 子查询
SELECT f.film_id, f.title,
       (SELECT COUNT(*) FROM film_actor fa WHERE fa.film_id = f.film_id) AS actor_cnt
FROM film f
WHERE f.rating = 'PG'
LIMIT 20;

-- @id: Q63
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: payment 主查询 + 相关子查询(嵌套两层)
SELECT p.payment_id, p.amount,
       (SELECT SUM(amount) FROM payment p2 WHERE p2.customer_id = p.customer_id AND p2.payment_date <= p.payment_date) AS running_total
FROM payment p
WHERE p.amount > 5.00
LIMIT 10;

-- =============================================================================
-- [SUBQ-006] Correlated subquery self-update — 2 queries
-- =============================================================================

-- @id: Q64
-- @target: SUBQ-006
-- @severity: critical
-- @scenario: rental.return_date 通过相关子查询自更新
UPDATE rental r
SET return_date = (
  SELECT MAX(payment_date)
  FROM payment p
  WHERE p.rental_id = r.rental_id
)
WHERE r.return_date IS NULL;

-- @id: Q65
-- @target: SUBQ-006
-- @severity: critical
-- @scenario: customer.active 通过 rental 计数自更新
UPDATE customer c
SET active = (
  SELECT COUNT(*) > 0
  FROM rental r
  WHERE r.customer_id = c.customer_id
);

-- =============================================================================
-- [REW-001] Large IN list not rewritten — 2 queries
-- =============================================================================

-- @id: Q66
-- @target: REW-001
-- @severity: warning
-- @scenario: film_id IN (...) 1000 个值
SELECT COUNT(*) FROM film WHERE film_id IN (
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
  21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
  41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60
);

-- @id: Q67
-- @target: REW-001
-- @severity: warning
-- @scenario: customer_id IN 大列表
SELECT COUNT(*) FROM customer WHERE customer_id IN (
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
  21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
);

-- =============================================================================
-- [VEC-001] Mixed vectorization/row engines — 3 queries
-- =============================================================================

-- @id: Q68
-- @target: VEC-001
-- @severity: info
-- @scenario: 普通 SELECT 触发 Row Adapter / Vector Adapter 切换
SELECT c.customer_id, f.title, r.rental_date
FROM customer c
JOIN rental r ON c.customer_id = r.customer_id
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f ON i.film_id = f.film_id
WHERE c.active = 1
LIMIT 20;

-- @id: Q69
-- @target: VEC-001
-- @severity: info
-- @scenario: 聚合查询触发 Row Adapter
SELECT c.customer_id, COUNT(*) AS cnt, SUM(p.amount) AS total
FROM customer c
JOIN payment p ON c.customer_id = p.customer_id
GROUP BY c.customer_id
LIMIT 20;

-- @id: Q70
-- @target: VEC-001
-- @severity: info
-- @scenario: 多表连接混合引擎
SELECT f.title, c.first_name, c.last_name
FROM film f, film_actor fa, actor a, inventory i, rental r, customer c
WHERE f.film_id = fa.film_id
  AND fa.actor_id = a.actor_id
  AND f.film_id = i.film_id
  AND i.inventory_id = r.inventory_id
  AND r.customer_id = c.customer_id
LIMIT 10;

-- =============================================================================
-- [AGG-001] Wrong aggregate strategy — 2 queries
-- =============================================================================

-- @id: Q71
-- @target: AGG-001
-- @severity: warning
-- @scenario: 大数据量 GROUP BY 走 GroupAggregate 而非 HashAggregate
SET enable_sort = off;
SELECT customer_id, COUNT(*) FROM rental GROUP BY customer_id LIMIT 20;
RESET enable_sort;

-- @id: Q72
-- @target: AGG-001
-- @severity: warning
-- @scenario: payment GROUP BY 排序聚合
SET enable_hashagg = off;
SELECT staff_id, COUNT(*) FROM payment GROUP BY staff_id LIMIT 10;
RESET enable_hashagg;

-- =============================================================================
-- [AGG-002] HashAggregate spill — 2 queries
-- =============================================================================

-- @id: Q73
-- @target: AGG-002
-- @severity: warning
-- @scenario: 大 GROUP BY + 低 work_mem
SET work_mem = '128kB';
SELECT customer_id, COUNT(*), SUM(amount), AVG(amount), MAX(amount), MIN(amount)
FROM payment
GROUP BY customer_id;
RESET work_mem;

-- @id: Q74
-- @target: AGG-002
-- @severity: warning
-- @scenario: 多列 GROUP BY
SET work_mem = '64kB';
SELECT customer_id, staff_id, COUNT(*), SUM(amount)
FROM payment
GROUP BY customer_id, staff_id;
RESET work_mem;

-- =============================================================================
-- [DIST-001] Poor distribution column — 2 queries
-- 注: 单节点下主要观察 explain 节点,真实分布键问题需多节点
-- =============================================================================

-- @id: Q75
-- @target: DIST-001
-- @severity: info
-- @scenario: payment 无分布键提示,触发重分布
SELECT p.payment_id, c.first_name
FROM payment p
JOIN customer c ON p.customer_id = c.customer_id
LIMIT 20;

-- @id: Q76
-- @target: DIST-001
-- @severity: info
-- @scenario: rental 无分布键提示
SELECT r.rental_id, i.film_id
FROM rental r
JOIN inventory i ON r.inventory_id = i.inventory_id
WHERE r.rental_date >= '2022-06-01'
LIMIT 20;

-- =============================================================================
-- [SKEW-001] Data skew — 2 queries
-- =============================================================================

-- @id: Q77
-- @target: SKEW-001
-- @severity: warning
-- @scenario: 按 customer_id 聚合,数据分布不均(部分客户消费多)
SELECT customer_id, COUNT(*) AS pay_cnt, SUM(amount) AS pay_total
FROM payment
GROUP BY customer_id
HAVING SUM(amount) > 30
LIMIT 10;

-- @id: Q78
-- @target: SKEW-001
-- @severity: warning
-- @scenario: rental 按 staff_id 聚合(staff 数量少,数据偏斜)
SELECT staff_id, COUNT(*) AS rental_cnt
FROM rental
GROUP BY staff_id;

-- =============================================================================
-- [STATS-001] Statistics not collected — 2 queries
-- =============================================================================

-- @id: Q79
-- @target: STATS-001
-- @severity: warning
-- @scenario: 删 stats 后统计列数为 0
DELETE STATISTICS payment;
SELECT COUNT(*) FROM payment WHERE amount > 5.00;

-- @id: Q80
-- @target: STATS-001
-- @severity: warning
-- @scenario: 删 stats 后 rental 估算异常
DELETE STATISTICS rental;
SELECT COUNT(*) FROM rental WHERE return_date IS NULL;

-- =============================================================================
-- [GEN-001] Plan depth too deep — 2 queries
-- =============================================================================

-- @id: Q81
-- @target: GEN-001
-- @severity: info
-- @scenario: 7 层以上嵌套查询
SELECT f.title
FROM film f
WHERE f.film_id IN (
  SELECT film_id FROM inventory WHERE inventory_id IN (
    SELECT inventory_id FROM rental WHERE customer_id IN (
      SELECT customer_id FROM customer WHERE store_id IN (
        SELECT store_id FROM store WHERE manager_staff_id IN (
          SELECT staff_id FROM staff WHERE active = true
        )
      )
    )
  )
)
LIMIT 10;

-- @id: Q82
-- @target: GEN-001
-- @severity: info
-- @scenario: 多层 CTE 嵌套
WITH t1 AS (SELECT customer_id FROM customer WHERE active = 1),
     t2 AS (SELECT t1.customer_id, COUNT(*) AS cnt FROM t1 JOIN rental r ON t1.customer_id = r.customer_id GROUP BY t1.customer_id),
     t3 AS (SELECT t2.customer_id, t2.cnt, COALESCE(p.total, 0) AS total FROM t2 LEFT JOIN (SELECT customer_id, SUM(amount) AS total FROM payment GROUP BY customer_id) p ON t2.customer_id = p.customer_id)
SELECT * FROM t3 WHERE total > 20 LIMIT 10;

-- =============================================================================
-- [HEALTHY] Healthy cases — 15 queries(不应触发任何规则,用于测误报率)
-- =============================================================================

-- @id: Q83
-- @target: NONE
-- @severity: info
-- @scenario: 小表 Seq Scan 是合理的(actor 200 行)
SELECT * FROM actor WHERE last_name = 'GUINESS';

-- @id: Q84
-- @target: NONE
-- @severity: info
-- @scenario: category 表全表(16 行,绝对合理)
SELECT * FROM category;

-- @id: Q85
-- @target: NONE
-- @severity: info
-- @scenario: country 表(109 行,全表 OK)
SELECT * FROM country WHERE country = 'United States';

-- @id: Q86
-- @target: NONE
-- @severity: info
-- @scenario: language 表(6 行)
SELECT * FROM language;

-- @id: Q87
-- @target: NONE
-- @severity: info
-- @scenario: film 主键点查
SELECT * FROM film WHERE film_id = 100;

-- @id: Q88
-- @target: NONE
-- @severity: info
-- @scenario: customer 主键点查
SELECT * FROM customer WHERE customer_id = 50;

-- @id: Q89
-- @target: NONE
-- @severity: info
-- @scenario: actor 主键点查
SELECT * FROM actor WHERE actor_id = 25;

-- @id: Q90
-- @target: NONE
-- @severity: info
-- @scenario: payment 主键点查(分区裁剪生效)
SELECT * FROM payment WHERE payment_date = '2022-03-15 10:00:00+00' AND payment_id = 1;

-- @id: Q91
-- @target: NONE
-- @severity: info
-- @scenario: 经典 Sakila 已优化查询:逾期未还
SELECT
    CONCAT(customer.last_name, ', ', customer.first_name) AS customer,
    address.phone,
    film.title
FROM rental
    INNER JOIN customer ON rental.customer_id = customer.customer_id
    INNER JOIN address ON customer.address_id = address.address_id
    INNER JOIN inventory ON rental.inventory_id = inventory.inventory_id
    INNER JOIN film ON inventory.film_id = film.film_id
WHERE rental.return_date IS NULL
    AND rental_date < CURRENT_DATE
ORDER BY title
LIMIT 5;

-- @id: Q92
-- @target: NONE
-- @severity: info
-- @scenario: payment 按月分区裁剪正确
SELECT COUNT(*) FROM payment WHERE payment_date >= '2022-03-01' AND payment_date < '2022-04-01';

-- @id: Q93
-- @target: NONE
-- @severity: info
-- @scenario: 全文检索使用 GIN 索引
SELECT title FROM film WHERE fulltext @@ to_tsquery('fate&india');

-- @id: Q94
-- @target: NONE
-- @severity: info
-- @scenario: film 索引列范围查(rating)
SELECT COUNT(*) FROM film WHERE rating = 'PG-13';

-- @id: Q95
-- @target: NONE
-- @severity: info
-- @scenario: film 索引列范围查(language_id)
SELECT COUNT(*) FROM film WHERE language_id = 1;

-- @id: Q96
-- @target: NONE
-- @severity: info
-- @scenario: payment 索引列范围查(customer_id)
SELECT COUNT(*) FROM payment WHERE customer_id = 50;

-- @id: Q97
-- @target: NONE
-- @severity: info
-- @scenario: rental 索引列精确查(inventory_id)
SELECT COUNT(*) FROM rental WHERE inventory_id = 100;

-- =============================================================================
-- [v3 Block 1] WINDOW 函数 — 8 queries
-- 覆盖: GEN-001 进阶用法
-- =============================================================================

-- @id: Q98
-- @target: GEN-001
-- @severity: info
-- @scenario: 客户消费 ROW_NUMBER 排行,触发 window operator + Sort
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    SUM(p.amount) AS total_spent,
    ROW_NUMBER() OVER (ORDER BY SUM(p.amount) DESC) AS rk
FROM customer c
JOIN payment p ON c.customer_id = p.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY rk
LIMIT 20;

-- @id: Q99
-- @target: GEN-001
-- @severity: info
-- @scenario: LAG 窗口函数,需 Sort + Window
SELECT
    payment_date,
    amount,
    COALESCE(LAG(amount, 1) OVER (ORDER BY payment_date), 0) AS prev_amount,
    amount - COALESCE(LAG(amount, 1) OVER (ORDER BY payment_date), 0) AS diff
FROM payment
WHERE customer_id = 1
ORDER BY payment_date
LIMIT 30;

-- @id: Q100
-- @target: GEN-001
-- @severity: info
-- @scenario: 累计 SUM OVER,触发 WindowAgg 节点
SELECT
    customer_id,
    payment_date,
    amount,
    SUM(amount) OVER (PARTITION BY customer_id ORDER BY payment_date) AS running_total
FROM payment
WHERE customer_id <= 5
ORDER BY customer_id, payment_date;

-- @id: Q101
-- @target: GEN-001
-- @severity: info
-- @scenario: RANK vs DENSE_RANK
SELECT
    film_id,
    title,
    rental_rate,
    RANK() OVER (ORDER BY rental_rate DESC) AS rk,
    DENSE_RANK() OVER (ORDER BY rental_rate DESC) AS drk
FROM film
WHERE rental_rate > 2.99
ORDER BY rental_rate DESC, film_id;

-- @id: Q102
-- @target: GEN-001
-- @severity: info
-- @scenario: NTILE 分四分位
SELECT
    film_id,
    title,
    length,
    NTILE(4) OVER (ORDER BY length) AS quartile
FROM film
ORDER BY length;

-- @id: Q103
-- @target: GEN-001
-- @severity: info
-- @scenario: FIRST_VALUE + DISTINCT
SELECT DISTINCT
    customer_id,
    FIRST_VALUE(payment_date) OVER (PARTITION BY customer_id ORDER BY payment_date) AS first_pay,
    LAST_VALUE(payment_date) OVER (PARTITION BY customer_id ORDER BY payment_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last_pay
FROM payment
WHERE customer_id <= 10;

-- @id: Q104
-- @target: GEN-001
-- @severity: info
-- @scenario: 7 天移动平均,frame clause
SELECT
    customer_id,
    payment_date,
    amount,
    AVG(amount) OVER (
        PARTITION BY customer_id
        ORDER BY payment_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS moving_avg_7
FROM payment
WHERE customer_id = 1
ORDER BY payment_date;

-- @id: Q105
-- @target: GEN-001
-- @severity: info
-- @scenario: 同一查询多个 window partition
SELECT
    staff_id,
    customer_id,
    amount,
    SUM(amount) OVER (PARTITION BY staff_id) AS staff_total,
    SUM(amount) OVER (PARTITION BY customer_id) AS cust_total
FROM payment
WHERE payment_date >= '2022-06-01' AND payment_date < '2022-07-01';

-- =============================================================================
-- [v3 Block 2] CTE 进阶 — 8 queries
-- 覆盖: GEN-001, SUBQ-001
-- =============================================================================

-- @id: Q106
-- @target: SCAN-004
-- @severity: warning
-- @scenario: 单 CTE + JOIN,大表 CTE 全扫
WITH high_value AS (
    SELECT customer_id, SUM(amount) AS total
    FROM payment
    GROUP BY customer_id
    HAVING SUM(amount) > 50
)
SELECT c.first_name, c.last_name, h.total
FROM customer c
JOIN high_value h ON c.customer_id = h.customer_id
ORDER BY h.total DESC
LIMIT 20;

-- @id: Q107
-- @target: SCAN-004
-- @severity: warning
-- @scenario: 多 CTE 链,每步都可能 SCAN-004
WITH
    active_customers AS (
        SELECT customer_id FROM customer WHERE active = 1
    ),
    recent_rentals AS (
        SELECT r.rental_id, r.customer_id
        FROM rental r
        WHERE r.customer_id IN (SELECT customer_id FROM active_customers)
    ),
    rental_stats AS (
        SELECT customer_id, COUNT(*) AS rental_count
        FROM recent_rentals
        GROUP BY customer_id
    )
SELECT * FROM rental_stats
ORDER BY rental_count DESC
LIMIT 20;

-- @id: Q108
-- @target: GEN-001
-- @severity: info
-- @scenario: CTE 引用多次,触发 Materialize
WITH store_stats AS (
    SELECT store_id, COUNT(*) AS staff_count
    FROM staff
    GROUP BY store_id
)
SELECT s1.store_id, s1.staff_count AS count_a, s2.staff_count AS count_b
FROM store_stats s1
JOIN store_stats s2 ON s1.store_id != s2.store_id;

-- @id: Q109
-- @target: GEN-001
-- @severity: info
-- @scenario: 递归 CTE,生成 1-10 序列
WITH RECURSIVE num_series AS (
    SELECT 1 AS n
    UNION ALL
    SELECT n + 1 FROM num_series WHERE n < 10
)
SELECT n FROM num_series;

-- @id: Q110
-- @target: GEN-001
-- @severity: info
-- @scenario: 递归 CTE + 时间序列
WITH RECURSIVE date_series AS (
    SELECT cast('2022-01-01' as timestamp) AS d
    UNION ALL
    SELECT d + INTERVAL '1 day' FROM date_series WHERE d < cast('2022-01-31' as timestamp)
)
SELECT cast(ds.d as date) AS d, COALESCE(SUM(p.amount), 0) AS daily_revenue
FROM date_series ds
LEFT JOIN payment p ON cast(p.payment_date as date) = cast(ds.d as date)
GROUP BY cast(ds.d as date)
ORDER BY d;

-- @id: Q111
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: CTE 嵌套 IN,相关子查询
WITH high_payers AS (
    SELECT customer_id, SUM(amount) AS total
    FROM payment
    GROUP BY customer_id
    HAVING SUM(amount) > 100
)
SELECT c.customer_id, c.first_name
FROM customer c
WHERE c.customer_id IN (SELECT customer_id FROM high_payers)
  AND EXISTS (SELECT 1 FROM rental r WHERE r.customer_id = c.customer_id);

-- @id: Q112
-- @target: GEN-001
-- @severity: info
-- @scenario: 嵌套 CTE
WITH outer_cte AS (
    WITH inner_cte AS (
        SELECT category_id, COUNT(*) AS film_count
        FROM film_category
        GROUP BY category_id
    )
    SELECT * FROM inner_cte WHERE film_count > 50
)
SELECT c.name, o.film_count
FROM category c
JOIN outer_cte o ON c.category_id = o.category_id
ORDER BY o.film_count DESC;

-- @id: Q113
-- @target: GEN-001
-- @severity: info
-- @scenario: CTE 链 + 多种聚合
WITH
    film_rental_count AS (
        SELECT i.film_id, COUNT(*) AS rental_count
        FROM inventory i
        JOIN rental r ON i.inventory_id = r.inventory_id
        GROUP BY i.film_id
    ),
    film_revenue AS (
        SELECT i.film_id, SUM(p.amount) AS total_revenue
        FROM inventory i
        JOIN rental r ON i.inventory_id = r.inventory_id
        JOIN payment p ON r.rental_id = p.rental_id
        GROUP BY i.film_id
    )
SELECT f.title, COALESCE(frc.rental_count, 0) AS rentals, COALESCE(fr.total_revenue, 0) AS revenue
FROM film f
LEFT JOIN film_rental_count frc ON f.film_id = frc.film_id
LEFT JOIN film_revenue fr ON f.film_id = fr.film_id
ORDER BY revenue DESC NULLS LAST
LIMIT 20;

-- =============================================================================
-- [v3 Block 3] LATERAL JOIN — 3 queries
-- 覆盖: SUBQ-001, GEN-001
-- =============================================================================

-- @id: Q114
-- @target: GEN-001
-- @severity: info
-- @scenario: LATERAL Top-N per group(每个客户消费最高的 3 笔)
SELECT c.customer_id, c.first_name, t.amount, t.payment_date
FROM customer c
CROSS JOIN LATERAL (
    SELECT amount, payment_date
    FROM payment
    WHERE customer_id = c.customer_id
    ORDER BY amount DESC
    LIMIT 3
) t
WHERE c.active = 1
ORDER BY c.customer_id, t.amount DESC;

-- @id: Q115
-- @target: SUBQ-001
-- @severity: info
-- @scenario: LATERAL 子查询聚合
SELECT f.film_id, f.title, s.actor_count, s.rental_count
FROM film f
LEFT JOIN LATERAL (
    SELECT
        (SELECT COUNT(*) FROM film_actor fa WHERE fa.film_id = f.film_id) AS actor_count,
        (SELECT COUNT(*) FROM inventory i WHERE i.film_id = f.film_id) AS rental_count
) s ON TRUE
ORDER BY f.film_id;

-- @id: Q116
-- @target: GEN-001
-- @severity: info
-- @scenario: LATERAL 取前 N 个 actor
SELECT f.film_id, f.title, a.actor_id, a.first_name
FROM film f
CROSS JOIN LATERAL (
    SELECT fa.actor_id, ac.first_name
    FROM film_actor fa
    JOIN actor ac ON fa.actor_id = ac.actor_id
    WHERE fa.film_id = f.film_id
    ORDER BY fa.actor_id
    LIMIT 3
) a
ORDER BY f.film_id;

-- =============================================================================
-- [v3 Block 4] Set Operations — 4 queries
-- 覆盖: GEN-001, SUBQ-001
-- =============================================================================

-- @id: Q117
-- @target: GEN-001
-- @severity: info
-- @scenario: UNION 合并 customer 和 staff
SELECT customer_id AS person_id, first_name AS name, 'customer' AS type
FROM customer
UNION
SELECT staff_id, first_name, 'staff' FROM staff
ORDER BY type, person_id;

-- @id: Q118
-- @target: SUBQ-001
-- @severity: info
-- @scenario: INTERSECT 找消费高的活跃客户
SELECT customer_id FROM customer WHERE active = 1
INTERSECT
SELECT customer_id FROM payment WHERE amount > 5;

-- @id: Q119
-- @target: SUBQ-001
-- @severity: info
-- @scenario: EXCEPT 找从未大额消费的活跃客户
SELECT customer_id FROM customer WHERE active = 1
EXCEPT
SELECT customer_id FROM payment WHERE amount > 5
ORDER BY customer_id
LIMIT 20;

-- @id: Q120
-- @target: GEN-001
-- @severity: info
-- @scenario: 混合 UNION + EXCEPT
SELECT actor_id FROM film_actor WHERE film_id = 1
UNION
SELECT actor_id FROM film_actor WHERE film_id = 2
EXCEPT
SELECT actor_id FROM film_actor WHERE film_id = 3
ORDER BY actor_id;

-- =============================================================================
-- [v3 Block 5] 子查询模式 — 6 queries
-- 覆盖: SUBQ-001, GEN-001
-- =============================================================================

-- @id: Q121
-- @target: SUBQ-001
-- @severity: info
-- @scenario: 标量子查询 in SELECT(N+1 反面教材)
SELECT f.film_id, f.title,
    (SELECT COUNT(*) FROM film_actor fa WHERE fa.film_id = f.film_id) AS actor_count,
    (SELECT COUNT(*) FROM inventory i WHERE i.film_id = f.film_id) AS inv_count
FROM film f
ORDER BY f.film_id
LIMIT 20;

-- @id: Q122
-- @target: SUBQ-001
-- @severity: info
-- @scenario: 相关子查询 in WHERE (EXISTS)
SELECT c.customer_id, c.first_name
FROM customer c
WHERE EXISTS (
    SELECT 1 FROM payment p
    WHERE p.customer_id = c.customer_id AND p.amount > 10
)
ORDER BY c.customer_id
LIMIT 20;

-- @id: Q123
-- @target: SUBQ-001
-- @severity: info
-- @scenario: NOT EXISTS 找从未租过碟的客户
SELECT c.customer_id, c.first_name
FROM customer c
WHERE NOT EXISTS (
    SELECT 1 FROM rental r WHERE r.customer_id = c.customer_id
)
ORDER BY c.customer_id
LIMIT 20;

-- @id: Q124
-- @target: SUBQ-001
-- @severity: info
-- @scenario: 子查询 in HAVING
SELECT customer_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM payment
GROUP BY customer_id
HAVING COUNT(*) > (
    SELECT AVG(c) FROM (
        SELECT COUNT(*) AS c FROM payment GROUP BY customer_id
    ) sub
)
ORDER BY cnt DESC
LIMIT 20;

-- @id: Q125
-- @target: GEN-001
-- @severity: info
-- @scenario: 派生表 in FROM
SELECT sub.customer_id, sub.cnt, sub.total
FROM (
    SELECT customer_id, COUNT(*) AS cnt, SUM(amount) AS total
    FROM payment
    GROUP BY customer_id
) sub
WHERE sub.cnt > 30
ORDER BY sub.cnt DESC;

-- @id: Q126
-- @target: SUBQ-001
-- @severity: info
-- @scenario: 相关子查询 in SELECT + WHERE
SELECT c.customer_id, c.first_name,
    (SELECT COUNT(*) FROM payment p WHERE p.customer_id = c.customer_id) AS pay_count,
    (SELECT MAX(payment_date) FROM payment p WHERE p.customer_id = c.customer_id) AS last_pay
FROM customer c
WHERE c.active = 1
  AND (SELECT COUNT(*) FROM payment p WHERE p.customer_id = c.customer_id) > 20
ORDER BY c.customer_id
LIMIT 20;

-- =============================================================================
-- [v3 Block 6] 聚合进阶 — 5 queries
-- 覆盖: AGG-001
-- =============================================================================

-- @id: Q127
-- @target: AGG-001
-- @severity: info
-- @scenario: GROUPING SETS 多维度汇总
SELECT
    staff_id,
    EXTRACT(YEAR FROM payment_date) AS yr,
    SUM(amount) AS total
FROM payment
GROUP BY GROUPING SETS (
    (staff_id),
    (yr),
    (staff_id, yr),
    ()
)
ORDER BY staff_id NULLS LAST, yr NULLS LAST;

-- @id: Q128
-- @target: AGG-001
-- @severity: info
-- @scenario: CUBE 二维全组合
SELECT
    staff_id,
    customer_id,
    SUM(amount) AS total,
    COUNT(*) AS cnt
FROM payment
WHERE payment_date >= '2022-06-01'
GROUP BY CUBE (staff_id, customer_id)
ORDER BY staff_id NULLS LAST, customer_id NULLS LAST
LIMIT 50;

-- @id: Q129
-- @target: AGG-001
-- @severity: info
-- @scenario: ROLLUP 层级汇总
SELECT
    staff_id,
    EXTRACT(MONTH FROM payment_date) AS m,
    SUM(amount) AS total
FROM payment
GROUP BY ROLLUP (staff_id, m)
ORDER BY staff_id NULLS LAST, m NULLS LAST;

-- @id: Q130
-- @target: AGG-001
-- @severity: info
-- @scenario: FILTER 子句条件聚合
SELECT
    staff_id,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE amount > 5) AS large_count,
    SUM(amount) FILTER (WHERE amount > 5) AS large_sum,
    COUNT(*) FILTER (WHERE amount < 2) AS small_count
FROM payment
GROUP BY staff_id
ORDER BY staff_id;

-- @id: Q131
-- @target: AGG-002
-- @severity: warning
-- @scenario: PERCENTILE 排序聚合(需 work_mem)
SET work_mem = '64kB';
SELECT
    customer_id,
    AVG(amount) AS avg_amount,
    MAX(amount) AS max_amount,
    MIN(amount) AS min_amount,
    STDDEV(amount) AS stddev_amount,
    COUNT(*) AS cnt
FROM payment
GROUP BY customer_id
HAVING COUNT(*) > 20
ORDER BY avg_amount DESC
LIMIT 20;
RESET work_mem;

-- =============================================================================
-- [v3 Block 7] 类型转换 — 3 queries
-- 覆盖: TYPE-001
-- =============================================================================

-- @id: Q132
-- @target: TYPE-001
-- @severity: warning
-- @scenario: 隐式 cast: payment_date 与 string 比较
SELECT * FROM payment WHERE payment_date > '2022-06-01';

-- @id: Q133
-- @target: TYPE-001
-- @severity: warning
-- @scenario: JOIN 条件中双侧 cast(强制 Seq Scan)
SELECT c.customer_id, c.first_name, p.amount
FROM customer c
JOIN payment p ON c.customer_id::text = p.customer_id::text
WHERE c.active = 1
ORDER BY p.amount DESC
LIMIT 20;

-- @id: Q134
-- @target: TYPE-001
-- @severity: info
-- @scenario: numeric 字段与 text 隐式类型转换
SELECT * FROM payment WHERE amount = '5.99';

-- =============================================================================
-- [v3 Block 8] 边界 case — 6 queries
-- =============================================================================

-- @id: Q135
-- @target: NONE
-- @severity: info
-- @scenario: 健康 - 空结果集
SELECT * FROM customer WHERE customer_id = -999;

-- @id: Q136
-- @target: NONE
-- @severity: info
-- @scenario: 健康 - 单行 PK 查询
SELECT * FROM film WHERE film_id = 1;

-- @id: Q137
-- @target: GEN-001
-- @severity: info
-- @scenario: DISTINCT ON 找每个客户最早一笔消费
SELECT DISTINCT ON (customer_id)
    customer_id, payment_date, amount
FROM payment
ORDER BY customer_id, payment_date;

-- @id: Q138
-- @target: JOIN-001
-- @severity: warning
-- @scenario: 自连接 - 同地址客户配对(NL)
SELECT c1.customer_id AS c1, c2.customer_id AS c2, c1.address_id
FROM customer c1
JOIN customer c2 ON c1.address_id = c2.address_id AND c1.customer_id < c2.customer_id
ORDER BY c1.address_id, c1.customer_id
LIMIT 20;

-- @id: Q139
-- @target: GEN-001
-- @severity: info
-- @scenario: 大 OFFSET 分页
SELECT * FROM payment ORDER BY payment_date LIMIT 20 OFFSET 5000;

-- @id: Q140
-- @target: GEN-001
-- @severity: info
-- @scenario: NULL 处理
SELECT COUNT(*) AS null_count
FROM customer
WHERE address_id IS NULL;

-- =============================================================================
-- [v3 Block 9] 真实场景模式 — 6 queries
-- =============================================================================

-- @id: Q141
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: N+1 反面教材 - 客户信息 + 多次子查询
SELECT c.customer_id, c.first_name,
    (SELECT MAX(payment_date) FROM payment WHERE customer_id = c.customer_id) AS last_pay,
    (SELECT MIN(payment_date) FROM payment WHERE customer_id = c.customer_id) AS first_pay,
    (SELECT COUNT(*) FROM rental WHERE customer_id = c.customer_id) AS rental_count,
    (SELECT SUM(amount) FROM payment WHERE customer_id = c.customer_id) AS total
FROM customer c
WHERE c.active = 1
ORDER BY c.customer_id
LIMIT 20;

-- @id: Q142
-- @target: GEN-001
-- @severity: info
-- @scenario: 时间序列日营收 dashboard
SELECT
    cast(payment_date as date) AS d,
    COUNT(*) AS txn_count,
    SUM(amount) AS revenue,
    AVG(amount) AS avg_txn
FROM payment
GROUP BY cast(payment_date as date)
ORDER BY d;

-- @id: Q143
-- @target: GEN-001
-- @severity: info
-- @scenario: Top-3 per group(window)
SELECT * FROM (
    SELECT
        customer_id, payment_date, amount,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY amount DESC) AS rk
    FROM payment
) t
WHERE rk <= 3
ORDER BY customer_id, rk;

-- @id: Q144
-- @target: GEN-001
-- @severity: info
-- @scenario: 漏斗分析:浏览 → 租碟 → 付费
SELECT
    c.customer_id,
    c.first_name,
    EXISTS(SELECT 1 FROM rental WHERE customer_id = c.customer_id) AS has_rented,
    EXISTS(SELECT 1 FROM payment WHERE customer_id = c.customer_id) AS has_paid,
    (SELECT COUNT(*) FROM rental WHERE customer_id = c.customer_id) AS rental_count
FROM customer c
WHERE c.active = 1
ORDER BY c.customer_id
LIMIT 20;

-- @id: Q145
-- @target: GEN-001
-- @severity: info
-- @scenario: 队列分析:按首次付费月份分组
SELECT
    DATE_TRUNC('month', first_payment) AS cohort,
    COUNT(*) AS cohort_size
FROM (
    SELECT customer_id, MIN(payment_date) AS first_payment
    FROM payment
    GROUP BY customer_id
) sub
GROUP BY DATE_TRUNC('month', first_payment)
ORDER BY cohort;

-- @id: Q146
-- @target: TYPE-004
-- @severity: warning
-- @scenario: 全字段模糊搜索(无索引)
SELECT * FROM film
WHERE title ILIKE '%love%' OR description ILIKE '%love%'
ORDER BY film_id
LIMIT 20;

-- =============================================================================
-- [v3 Block 10] 0% 触发规则补强 — 10 queries
-- 覆盖: GEN-001, MEM-004, PUSH-001, SORT-003, SUBQ-001, VEC-001, SKEW-001
-- =============================================================================

-- @id: Q147
-- @target: GEN-001
-- @severity: warning
-- @scenario: 笛卡尔积 + 后期过滤(效率极低)
SELECT f.title, COUNT(*) AS rental_count
FROM film f, inventory i, rental r
WHERE f.film_id = i.film_id AND i.inventory_id = r.inventory_id
GROUP BY f.film_id, f.title
HAVING COUNT(*) > 20
ORDER BY rental_count DESC
LIMIT 20;

-- @id: Q148
-- @target: MEM-004
-- @severity: warning
-- @scenario: 大 Hash 表 + 多表 JOIN
SET work_mem = '64kB';
SELECT /*+ HashJoin */ c.customer_id, c.first_name, c.last_name, COUNT(*) AS pay_count
FROM customer c
JOIN rental r ON c.customer_id = r.customer_id
JOIN payment p ON r.rental_id = p.rental_id
GROUP BY c.customer_id, c.first_name, c.last_name
ORDER BY pay_count DESC
LIMIT 10;
RESET work_mem;

-- @id: Q149
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 谓词包装在函数里,阻止索引下推
SELECT COUNT(*) FROM payment
WHERE EXTRACT(MONTH FROM payment_date) = 6
  AND EXTRACT(YEAR FROM payment_date) = 2022;

-- @id: Q150
-- @target: SORT-003
-- @severity: warning
-- @scenario: 重复排序(子查询 ORDER BY 后再 ORDER BY)
SELECT t1.customer_id, t1.amount, t2.amount
FROM (
    SELECT customer_id, amount FROM payment ORDER BY amount DESC LIMIT 10
) t1
JOIN (
    SELECT customer_id, amount FROM payment ORDER BY amount DESC LIMIT 10
) t2 USING (customer_id)
ORDER BY t1.amount DESC, t2.amount DESC;

-- @id: Q151
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: 跨列相关子查询,无法提升
SELECT c.customer_id, c.first_name
FROM customer c
WHERE c.customer_id IN (
    SELECT r.customer_id
    FROM rental r
    WHERE r.staff_id <> c.store_id
)
ORDER BY c.customer_id
LIMIT 20;

-- @id: Q152
-- @target: VEC-001
-- @severity: warning
-- @scenario: 强制使用行存引擎
SET enable_vector_engine = off;
SELECT COUNT(*), AVG(amount), SUM(amount)
FROM payment;
SET enable_vector_engine = on;

-- @id: Q153
-- @target: SKEW-001
-- @severity: warning
-- @scenario: payment 表 customer_id 倾斜(Top 客户消费笔数)
SELECT customer_id, COUNT(*) AS cnt, SUM(amount) AS total
FROM payment
GROUP BY customer_id
ORDER BY cnt DESC
LIMIT 5;

-- @id: Q154
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 类型转换阻止下推
SELECT * FROM payment
WHERE amount::text LIKE '5.%'
ORDER BY payment_date
LIMIT 20;

-- @id: Q155
-- @target: PUSH-002
-- @severity: warning
-- @scenario: 多表 JOIN 无合适分布键
SELECT co.country, COUNT(c.customer_id) AS cust_count
FROM country co
JOIN city ci ON ci.country_id = co.country_id
JOIN address a ON a.city_id = ci.city_id
JOIN customer c ON c.address_id = a.address_id
GROUP BY co.country
ORDER BY cust_count DESC;

-- @id: Q156
-- @target: GEN-001
-- @severity: warning
-- @scenario: 优化器通常会简化但仍可能有问题
SELECT
    f.title,
    COUNT(r.rental_id) AS times_rented,
    AVG(p.amount) AS avg_pay
FROM film f
LEFT JOIN inventory i ON f.film_id = i.film_id
LEFT JOIN rental r ON i.inventory_id = r.inventory_id
LEFT JOIN payment p ON r.rental_id = p.rental_id
WHERE f.release_year = 2006
GROUP BY f.film_id, f.title
ORDER BY times_rented DESC
LIMIT 20;

-- =============================================================================
-- [v3 Block 11] 健康 case 补强 — 3 queries
-- =============================================================================

-- @id: Q157
-- @target: NONE
-- @severity: info
-- @scenario: 健康 - 简单聚合 + 索引列
SELECT COUNT(*), AVG(amount) FROM payment WHERE staff_id = 1;

-- @id: Q158
-- @target: NONE
-- @severity: info
-- @scenario: 健康 - 索引等值连接
SELECT f.title, c.name
FROM film f
JOIN film_category fc ON f.film_id = fc.film_id
JOIN category c ON fc.category_id = c.category_id
WHERE c.name = 'Drama'
LIMIT 20;

-- @id: Q159
-- @target: NONE
-- @severity: info
-- @scenario: 健康 - 简单 TOP-N 用索引
SELECT * FROM rental ORDER BY rental_date DESC LIMIT 10;

-- =============================================================================
-- [v3.1 Block 12] 分区索引 / 全局索引 — 12 queries
-- 覆盖: PART-001, SCAN-001, SCAN-004, GEN-001
-- 测试: 局部 vs 全局索引/复合索引/位图/表达式/部分/HASH 索引
-- 依赖: 部分 query 假设索引已创建(测试中 _auto_eval 期望 GT 给 "should create index" 建议)
-- =============================================================================

-- @id: Q160
-- @target: PART-001
-- @severity: info
-- @scenario: 局部分区索引 seek(单分区)
CREATE INDEX IF NOT EXISTS idx_payment_date ON payment (payment_date) LOCAL;
SELECT * FROM payment WHERE payment_date BETWEEN '2022-06-01' AND '2022-06-30';

-- @id: Q161
-- @target: SCAN-004
-- @severity: warning
-- @scenario: 跨分区查询,customer_id 无全局索引(只有局部索引)
--           预期: 所有 7 个分区都走索引(可能全表扫,因 customer_id 分布广)
SELECT * FROM payment WHERE customer_id = 1 ORDER BY payment_date DESC LIMIT 20;

-- @id: Q162
-- @target: SCAN-004
-- @severity: info
-- @scenario: Index-only scan(covering index)
CREATE INDEX IF NOT EXISTS idx_payment_cust_amt_date ON payment (customer_id);
SELECT customer_id, amount, payment_date FROM payment WHERE customer_id <= 5 ORDER BY payment_date;

-- @id: Q163
-- @target: GEN-001
-- @severity: info
-- @scenario: Bitmap OR scan(多条件 OR)
SELECT * FROM payment WHERE customer_id = 1 OR staff_id = 1;

-- @id: Q164
-- @target: SCAN-004
-- @severity: warning
-- @scenario: 表达式索引(LOWER 包装,无索引会全表扫)
CREATE INDEX IF NOT EXISTS idx_customer_email_lower ON customer (LOWER(email));
SELECT * FROM customer WHERE LOWER(email) LIKE '%@example.org';

-- @id: Q165
-- @target: PART-001
-- @severity: info
-- @scenario: 复合索引 leading column 命中
CREATE INDEX IF NOT EXISTS idx_payment_cust_date ON payment (customer_id, payment_date);
SELECT * FROM payment WHERE customer_id = 1 AND payment_date >= '2022-06-01' ORDER BY payment_date LIMIT 10;

-- @id: Q166
-- @target: SCAN-004
-- @severity: warning
-- @scenario: 复合索引非 leading column(无法用上索引,全表扫)
--           索引 idx_payment_cust_date (customer_id, payment_date) 只用 payment_date
SELECT * FROM payment WHERE payment_date = '2022-06-15';

-- @id: Q167
-- @target: SCAN-004
-- @severity: info
-- @scenario: 部分索引(带 WHERE 谓词)
CREATE INDEX IF NOT EXISTS idx_payment_large ON payment (customer_id);
SELECT * FROM payment WHERE customer_id = 1 AND amount > 5;

-- @id: Q168
-- @target: SCAN-004
-- @severity: warning
-- @scenario: HASH 函数索引(无索引)
SELECT * FROM customer WHERE HASHTEXT(email) = 1234567890;

-- @id: Q169
-- @target: SCAN-004
-- @severity: info
-- @scenario: 复合索引 (a, b, c) 仅用 c(无 leading)
CREATE INDEX IF NOT EXISTS idx_film_title_year_rate ON film (title, release_year, rental_rate);
SELECT * FROM film WHERE rental_rate = 0.99 LIMIT 10;

-- @id: Q170
-- @target: PART-001
-- @severity: info
-- @scenario: 全局索引 + 分区剪枝(组合)
SELECT * FROM payment
WHERE customer_id = 1
  AND payment_date >= '2022-01-01'
  AND payment_date < '2022-04-01';

-- @id: Q171
-- @target: GEN-001
-- @severity: info
-- @scenario: Index scan + heap fetch(非 index-only)
CREATE INDEX IF NOT EXISTS idx_film_rating ON film (rating);
SELECT film_id, title, rental_rate, length FROM film WHERE rating = 'PG-13' LIMIT 10;

-- =============================================================================
-- [v3.1 Block 13] UPDATE SET 多字段带子查询 — 12 queries
-- 覆盖: SUBQ-001, SUBQ-006, PART-001, GEN-001
-- 测试: 标量 SET/多字段 SET/相关子查询/UPDATE FROM/NOT IN/EXISTS/CTE/RETURNING
-- =============================================================================

-- @id: Q172
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: UPDATE SET col = 标量子查询(单行)
UPDATE film
SET release_year = 2020
WHERE film_id = (SELECT film_id FROM film ORDER BY film_id DESC LIMIT 1);

-- @id: Q173
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: UPDATE SET 多字段 + 多个子查询
UPDATE customer
SET
    address_id = (SELECT address_id FROM address ORDER BY address_id DESC LIMIT 1),
    last_update = NOW()
WHERE customer_id = 1;

-- @id: Q174
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: UPDATE 嵌套相关子查询(多层)
UPDATE customer c
SET address_id = (
    SELECT address_id FROM address a
    WHERE a.city_id = (
        SELECT city_id FROM city WHERE city = 'London' LIMIT 1
    )
    LIMIT 1
)
WHERE c.active = 1;

-- @id: Q175
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: UPDATE FROM + 聚合子查询
UPDATE customer c
SET active = 0
FROM (
    SELECT customer_id FROM payment
    GROUP BY customer_id
    HAVING SUM(amount) > 100
) sub
WHERE c.customer_id = sub.customer_id;

-- @id: Q176
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: UPDATE WHERE NOT IN 子查询
UPDATE film
SET rental_rate = rental_rate * 0.9
WHERE film_id NOT IN (
    SELECT i.film_id FROM inventory i
    JOIN rental r ON i.inventory_id = r.inventory_id
    WHERE r.rental_date >= '2022-06-01'
);

-- @id: Q177
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: UPDATE WHERE EXISTS 相关子查询
UPDATE film f
SET rental_rate = rental_rate * 1.1
WHERE EXISTS (
    SELECT 1 FROM film_actor fa
    WHERE fa.film_id = f.film_id
      AND fa.actor_id < 5
);

-- @id: Q178
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: UPDATE WITH CTE
WITH high_renters AS (
    SELECT customer_id, COUNT(*) AS cnt
    FROM rental
    GROUP BY customer_id
    HAVING COUNT(*) > 30
)
UPDATE customer c
SET active = 0
FROM high_renters h
WHERE c.customer_id = h.customer_id;

-- @id: Q179
-- @target: PART-001
-- @severity: warning
-- @scenario: UPDATE 分区表(单分区操作)
UPDATE payment
SET amount = ROUND(amount * 0.9, 2)
WHERE payment_date >= '2022-06-01' AND payment_date < '2022-07-01';

-- @id: Q180
-- @target: GEN-001
-- @severity: warning
-- @scenario: UPDATE 多字段 FROM JOIN
UPDATE inventory i
SET
    store_id = s.store_id,
    last_update = NOW()
FROM staff s
WHERE i.store_id = 1 AND s.staff_id = 1;

-- @id: Q181
-- @target: GEN-001
-- @severity: info
-- @scenario: UPDATE ... RETURNING(返回修改行)
UPDATE customer
SET last_update = NOW()
WHERE customer_id = 1
RETURNING customer_id, first_name, last_update;

-- @id: Q182
-- @target: GEN-001
-- @severity: info
-- @scenario: UPDATE SET with CASE WHEN
UPDATE customer
SET active = CASE
    WHEN customer_id <= 100 THEN 1
    WHEN customer_id <= 300 THEN 0
    ELSE 1
END;

-- @id: Q183
-- @target: SUBQ-001
-- @severity: warning
-- @scenario: UPDATE WITH RECURSIVE CTE
WITH RECURSIVE chain AS (
    SELECT customer_id, 1 AS depth
    FROM customer
    WHERE active = 1
    UNION ALL
    SELECT r.customer_id, c.depth + 1
    FROM chain c
    JOIN rental r ON r.customer_id = c.customer_id
    WHERE c.depth < 3
)
UPDATE customer cu
SET last_update = NOW()
FROM chain ch
WHERE cu.customer_id = ch.customer_id;

-- =============================================================================
-- [v3.1 Block 14] 多层嵌套视图不下推 — 10 queries
-- 覆盖: PUSH-001, PUSH-002, GEN-001
-- 测试: 1-3 层视图/聚合视图/DISTINCT/标量子查询/HAVING/UNION
-- 依赖: 需要 run_explain.py 支持 CREATE VIEW(已加,见脚本注释)
-- =============================================================================

-- @id: Q184
-- @target: GEN-001
-- @severity: info
-- @scenario: 1 层视图 + WHERE 谓词(正例: 谓词可下推)
CREATE OR REPLACE VIEW v_customer_rentals AS
SELECT c.customer_id, c.first_name, c.last_name, COUNT(r.rental_id) AS rental_count
FROM customer c
LEFT JOIN rental r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name;
SELECT * FROM v_customer_rentals WHERE customer_id = 1;

-- @id: Q185
-- @target: GEN-001
-- @severity: info
-- @scenario: 2 层嵌套视图(内联定义,v_customer_rentals 原为 Q184 创建)+ WHERE(测试是否下推到内层)
CREATE OR REPLACE VIEW v_top_customers AS
SELECT c.customer_id, c.first_name, c.last_name, COUNT(r.rental_id) AS rental_count
FROM customer c
LEFT JOIN rental r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(r.rental_id) > 10;
SELECT * FROM v_top_customers WHERE customer_id <= 5;

-- @id: Q186
-- @target: GEN-001
-- @severity: info
-- @scenario: 3 层嵌套视图(内联定义,v_top_customers 原为 Q185 创建,深度测试)
CREATE OR REPLACE VIEW v_top_active AS
SELECT c.customer_id, c.first_name, c.last_name, COUNT(r.rental_id) AS rental_count
FROM customer c
LEFT JOIN rental r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(r.rental_id) > 20;
SELECT * FROM v_top_active WHERE customer_id = 1;

-- @id: Q187
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 视图内层有 GROUP BY(反例: 谓词无法下推到聚合)
CREATE OR REPLACE VIEW v_film_revenue AS
SELECT f.film_id, f.title, SUM(p.amount) AS total_revenue
FROM film f
JOIN inventory i ON f.film_id = i.film_id
JOIN rental r ON i.inventory_id = r.inventory_id
JOIN payment p ON r.rental_id = p.rental_id
GROUP BY f.film_id, f.title;
SELECT * FROM v_film_revenue WHERE film_id = 1;

-- @id: Q188
-- @target: GEN-001
-- @severity: info
-- @scenario: 视图内 UNION(正例: 谓词下推到每个分支)
CREATE OR REPLACE VIEW v_people AS
SELECT customer_id AS id, first_name, last_name, 'customer' AS type FROM customer
UNION ALL
SELECT staff_id, first_name, last_name, 'staff' FROM staff;
SELECT * FROM v_people WHERE id = 1;

-- @id: Q189
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 视图内含标量子查询(反例: 外层谓词无法下推)
CREATE OR REPLACE VIEW v_customer_pay_count AS
SELECT c.customer_id, c.first_name,
    (SELECT COUNT(*) FROM payment p WHERE p.customer_id = c.customer_id) AS pay_count
FROM customer c;
SELECT * FROM v_customer_pay_count WHERE customer_id <= 10;

-- @id: Q190
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 视图套分区表 + 谓词(反例: 谓词不下推导致全分区扫)
CREATE OR REPLACE VIEW v_payment_2022 AS
SELECT * FROM payment WHERE payment_date >= '2022-01-01';
SELECT * FROM v_payment_2022 WHERE payment_date >= '2022-06-01';

-- @id: Q191
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 视图内 DISTINCT(反例: 谓词不下推)
CREATE OR REPLACE VIEW v_distinct_customers AS
SELECT DISTINCT customer_id, first_name FROM customer;
SELECT * FROM v_distinct_customers WHERE customer_id <= 5;

-- @id: Q192
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 视图内 LIMIT(反例: LIMIT 阻止谓词下推)
CREATE OR REPLACE VIEW v_top10_films AS
SELECT film_id, title, rental_rate FROM film ORDER BY rental_rate DESC LIMIT 10;
SELECT * FROM v_top10_films WHERE film_id = 1;

-- @id: Q193
-- @target: PUSH-001
-- @severity: warning
-- @scenario: 视图内 HAVING(反例: HAVING 阻止外层谓词下推)
CREATE OR REPLACE VIEW v_high_value_customers AS
SELECT customer_id, SUM(amount) AS total
FROM payment
GROUP BY customer_id
HAVING SUM(amount) > 50;
SELECT * FROM v_high_value_customers WHERE customer_id = 1;

-- =============================================================================
-- 结束 - v3.1 共 34 条新 query (Q160-Q193),累计 193 条
-- =============================================================================

-- =============================================================================
-- 结束 - v3.1 共 34 条新 query (Q160-Q193),累计 193 条
-- =============================================================================