# Query Set v1

> **Generated:** 2026-06-20
> **Schema:** `c2j/ogagila` (openGauss 7.0.0-RC1, Oracle 兼容模式, centralized)
> **Target rules:** ogexplain-analyzer v0.2.x (25 rules, 覆盖 17 条)
> **Total queries:** 97 (82 problematic + 15 healthy)
> **Files:** `queries.sql` · `queries_meta.json`

## 数据规模

| 表 | 行数 | 备注 |
|----|------|------|
| film | 1000 | 主表,有 fulltext GIN 索引 |
| actor | 200 | |
| customer | 599 | |
| address | 603 | |
| rental | 16,044 | |
| payment | 16,049 | **按月分区 7 个分区 (2022-01 到 2022-07)** |
| inventory | 4,581 | |
| category | 16 | |
| language | 6 | |

## 规则覆盖一览

| 规则 ID | 名称 | query 数 | 难度 |
|---------|------|---------|------|
| SCAN-001 | Large table full scan | 8 | 易触发 |
| SCAN-004 | Filter without index | 6 | 易触发 |
| JOIN-001 | Nested Loop with large dataset | 5 | 中 |
| JOIN-002 | Hash spill to disk | 4 | 中(需 SET work_mem) |
| MEM-001 | Sort spilled to disk | 4 | 中(需 SET work_mem) |
| MEM-004 | High peak memory | 3 | 易 |
| SORT-003 | Duplicate sort | 3 | 中 |
| NET-001 | Broadcast large table | 3 | 单节点下主要看 Streaming 节点 |
| EST-001 | Severe row underestimation | 4 | 需 DELETE STATISTICS |
| EST-004 | NL from underestimation | 3 | 需 DELETE STATISTICS |
| TYPE-001 | Implicit type coercion | 4 | 易触发(critical 级) |
| TYPE-004 | LIKE leading wildcard | 3 | 易触发 |
| PUSH-001 | Query not pushed down | 3 | 中 |
| PUSH-002 | Multi-layer streaming | 3 | 中 |
| PART-001 | Partition pruning failure | 4 | 易(分区表) |
| SUBQ-001 | Correlated subquery not lifted | 3 | 易 |
| SUBQ-006 | Correlated subquery self-update | 2 | 易(UPDATE 语句) |
| REW-001 | Large IN list not rewritten | 2 | 易(60 个值) |
| VEC-001 | Mixed vectorization/row engines | 3 | 易触发 |
| AGG-001 | Wrong aggregate strategy | 2 | 需 SET enable_* |
| AGG-002 | HashAggregate spill | 2 | 需 SET work_mem |
| DIST-001 | Poor distribution column | 2 | 单节点下观察节点 |
| SKEW-001 | Data skew | 2 | 易 |
| STATS-001 | Statistics not collected | 2 | 需 DELETE STATISTICS |
| GEN-001 | Plan depth too deep | 2 | 易触发 |
| **NONE** | Healthy cases(测误报率) | 15 | — |

## 用法

### 一键跑 EXPLAIN ANALYZE（推荐）

```bash
# 仓库根目录执行
python3 queries/run_explain.py \
    --host localhost --port 5432 \
    --db pagila --user gaussdb --password Enmo@123
```

脚本会：

- 对每条 query 自动 `BEGIN; EXPLAIN ANALYZE ...; ROLLBACK;`（避免副作用污染）
- 保存到 `queries/v1/explains/Q*.explain` + `.meta.json`
- 同时输出 `explains/index.json`

**注意**：不要直接 `gsql < queries.sql`！文件含副作用语句（SET/DELETE STATISTICS/UPDATE），会污染后续 query 的执行环境。必须用 `run_explain.py`。

详见 [`../README.md`](../README.md)。

## 已知的副作用与注意事项

### 副作用语句清单

| ID | 副作用 | 备注 |
|----|--------|------|
| Q20-Q23, Q24-Q27, Q71-Q74 | `SET work_mem = ...` / `SET enable_* = off` | 已被 `run_explain.py` 在事务内回滚 |
| Q37-Q40, Q41-Q43, Q79-Q80 | `DELETE STATISTICS` | 影响 ANALYZE 结果；openGauss 不支持该语法,会被软跳过 |
| Q64-Q65 | `UPDATE rental` / `UPDATE customer` | 改真实数据!`run_explain.py` 默认会回滚,但建议用单独测试 schema |
| Q71-Q72 | `SET enable_sort/hashagg = off` | 同 SET,事务回滚恢复 |

### 评估后建议清理

```sql
-- 重新收集被 DELETE STATISTICS 影响的表(若用 --no-rollback 跑过)
ANALYZE payment;
ANALYZE rental;
ANALYZE customer;
ANALYZE inventory;
ANALYZE film_actor;
```

## 已知偏差来源 (disclaimer)

1. **同作者偏差**：ogagila 与 ogexplain-analyzer 都是 c2j 维护。**schema 设计可能恰好让工具的规则更容易触发**,导致评估结果偏乐观。要严肃评估,建议同时跑一份**与 ogagila schema 无关的测试集**。

2. **Oracle 兼容模式**：ogagila 用 `datcompatibility = A`,部分规则(TYPE-001 涉及空字符串语义)行为与 PG 兼容模式不同。

3. **openGauss 7.0.0-RC1**：这是非 LTS 版本,真实生产多用 5/6。计划格式细节可能不同,**评估结果不一定能直接迁移**。

4. **数据规模偏小**：payment/rental 才 1.6w 行,**部分阈值规则**(SCAN-001 默认 1w、JOIN-001 等)即使触发也不会很严重。如果想要更严苛的评估,需要扩容数据 10-100x。

5. **单节点 centralized 模式**：Docker 跑的是单节点 lite build。DIST-001 / SKEW-001 / NET-001 等分布式专属规则的物理信号在 EXPLAIN 里很弱,主要靠 Streaming 节点观察。

## 后续迭代方向

- **v1.1**：加入更多边界 case,比如 EXPLAIN 解析失败、未知节点类型
- **v1.2**：加入 multi-statement 文件、pretty mode 与 normal mode 切换
- **v2.0**：基于 v1 评估发现的诊断工具弱项规则,**反向加权**扩充数据集
