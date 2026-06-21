-- =============================================================================
-- ogexplain-analyzer Ground Truth Query Set v1
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
-- 结束 - 共 97 条 query
-- =============================================================================