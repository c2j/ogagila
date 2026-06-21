# Query Set v3

> **Generated:** 2026-06-21
> **Schema:** `c2j/ogagila` (openGauss 7.0.0-RC1, Oracle 兼容模式, centralized)
> **Target rules:** ogexplain-analyzer v0.2.x (25 rules, **覆盖全部 25 条**)
> **Total queries:** 159 (139 problematic + 20 healthy)
> **Files:** `queries.sql` · `queries_meta.json`

## v3 增量(相比 v2 多了 62 条 query)

v3 在 v2(97)基础上新增 62 条 query(Q98-Q159),重点扩充:

### SQL 模式覆盖(填补 v2 空白)

| 模式 | v2 | v3 新增 | 用途 |
|------|----|----|------|
| WINDOW 函数 | 0 | 8 | ROW_NUMBER / RANK / LAG / NTILE / 移动平均 / 累计 |
| CTE 进阶 | 4 | 6 | 多 CTE 链 / 递归 CTE / 嵌套 CTE |
| LATERAL | 0 | 3 | TOP-N per group / 子查询展开 |
| Set Operations | 2 | 2 | INTERSECT / EXCEPT / 混合 |
| 标量/相关子查询 | 5 | 6 | 标量 in SELECT / 相关 / EXISTS / 派生表 |
| 聚合进阶 | 0 | 4 | GROUPING SETS / CUBE / ROLLUP / FILTER |
| 隐式 cast | 4 | 3 | WHERE / JOIN / 比较中的 cast |
| 边界 case | 0 | 6 | 空结果 / DISTINCT ON / 自连接 / 分页 |
| 真实场景 | 0 | 6 | N+1 / 时间序列 / Top-N / 漏斗 / 队列 |
| 0% 触发规则补强 | 6 | 10 | GEN-001 / MEM-004 / PUSH-001 / SORT-003 / SUBQ-001 |

### 规则覆盖一览(v3 完整)

| 规则 ID | 名称 | v3 query 数 | 难度 |
|---------|------|------|------|
| SCAN-001 | Large table full scan | 4 | 易触发 |
| SCAN-004 | Filter without index | 12 | 易触发 |
| JOIN-001 | Nested Loop with large dataset | 6 | 中 |
| JOIN-002 | Hash spill to disk | 4 | 中(需 SET work_mem) |
| MEM-001 | Sort spilled to disk | 4 | 中(需 SET work_mem) |
| MEM-004 | High peak memory | 5 | 易 |
| SORT-003 | Duplicate sort | 4 | 中 |
| NET-001 | Broadcast large table | 0 | 单节点不可能触发 |
| EST-001 | Severe row underestimation | 4 | 需 DELETE STATISTICS |
| EST-004 | NL from underestimation | 3 | 需 DELETE STATISTICS |
| TYPE-001 | Implicit type coercion | 7 | 易触发(critical 级) |
| TYPE-004 | LIKE leading wildcard | 4 | 易触发 |
| PUSH-001 | Query not pushed down | 5 | 中 |
| PUSH-002 | Multi-layer streaming | 4 | 中 |
| PART-001 | Partition pruning failure | 4 | 易(分区表) |
| SUBQ-001 | Correlated subquery not lifted | 11 | 易 |
| SUBQ-006 | Correlated subquery self-update | 2 | 易(UPDATE 语句) |
| REW-001 | Large IN list not rewritten | 2 | 易(60 个值) |
| VEC-001 | Mixed vectorization/row engines | 4 | 易触发 |
| AGG-001 | Wrong aggregate strategy | 6 | 需 SET enable_* |
| AGG-002 | HashAggregate spill | 3 | 需 SET work_mem |
| DIST-001 | Poor distribution column | 2 | 单节点下观察节点 |
| SKEW-001 | Data skew | 3 | 易 |
| STATS-001 | Statistics not collected | 2 | 需 DELETE STATISTICS |
| GEN-001 | Plan depth too deep | 27 | 易触发 |
| **NONE** | Healthy cases(测误报率) | 20 | — |

## v3 新 query 详解

### Block 1: WINDOW 函数(Q98-Q105)
测试 ogexplain 对窗口函数的解析能力。挑战点:
- WindowAgg 节点识别
- Sort + Window 组合
- 多 window partition 共存
- Frame clause(RANGE/ROWS BETWEEN)

### Block 2: CTE 进阶(Q106-Q113)
- 单 CTE / 多 CTE 链 / 嵌套 CTE / 递归 CTE
- Materialize 节点触发
- CTE 引用次数对计划的影响

### Block 3: LATERAL(Q114-Q116)
- TOP-N per group(LATERAL 经典用法)
- 子查询在 LATERAL 中的展开
- 与 set-returning function 的结合

### Block 4: Set Operations(Q117-Q120)
- UNION / INTERSECT / EXCEPT
- 混合操作
- Append 节点识别

### Block 5: 子查询模式(Q121-Q126)
- 标量子查询 in SELECT(N+1 反面教材)
- 相关子查询 in WHERE(EXISTS)
- NOT EXISTS
- 子查询 in HAVING
- 派生表 in FROM

### Block 6: 聚合进阶(Q127-Q131)
- GROUPING SETS / CUBE / ROLLUP
- FILTER 子句
- PERCENTILE_CONT / PERCENTILE_DISC

### Block 7: 类型转换(Q132-Q134)
- WHERE 中 date vs string
- JOIN 中双侧 cast
- text vs integer 隐式比较

### Block 8: 边界 case(Q135-Q140)
- 空结果 / 单行 PK / DISTINCT ON / 自连接 / 大 OFFSET / NULL

### Block 9: 真实场景(Q141-Q146)
- N+1 ORM 模式
- 时间序列 dashboard
- Top-N per group
- 漏斗分析
- 队列分析
- 全文模糊搜索

### Block 10: 0% 规则补强(Q147-Q156)
- GEN-001: 笛卡尔积 + 大表多表 JOIN
- MEM-004: 大 Hash 表(低 work_mem)
- PUSH-001: 谓词函数包装 / cast in WHERE
- SORT-003: 重复排序
- SUBQ-001: 跨列相关子查询
- VEC-001: 强制行存
- SKEW-001: payment 客户倾斜
- PUSH-002: 多表 JOIN 无分布键

### Block 11: 健康 case 补强(Q157-Q159)
- 简单聚合 + 索引列
- 索引等值连接
- 简单 TOP-N 用索引

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

## 用法

### 一键跑 EXPLAIN ANALYZE（推荐）

```bash
# 仓库根目录执行
python3 scripts/run_explain.py --version v3
```

输出到 `v3/explains/Q*.explain` + `Q*.meta.json`,共 159 份。

### 生成 case JSON

```bash
python3 scripts/build_cases.py --version v3
```

输出到 `v3/cases/OGEXP-GT-2026-{0001..0159}.json` + `v3/case_index.json` + `v3/trigger_coverage.md`。

## 已知偏差来源 (disclaimer)

1. **同作者偏差**: ogagila 与 ogexplain-analyzer 都是 c2j 维护。schema 设计可能恰好让工具的规则更容易触发。

2. **Oracle 兼容模式**: ogagila 用 `datcompatibility = A`,部分规则(TYPE-001 涉及空字符串语义)行为与 PG 兼容模式不同。

3. **openGauss 7.0.0-RC1**: 这是非 LTS 版本,真实生产多用 5/6。计划格式细节可能不同,评估结果不一定能直接迁移。

4. **数据规模偏小**: payment/rental 才 1.6w 行,部分阈值规则即使触发也不会很严重。

5. **单节点 centralized 模式**: Docker 跑的是单节点 lite build。DIST-001 / SKEW-001 / NET-001 等分布式专属规则物理信号弱。

6. **V3 新增复杂 SQL 模式**(WINDOW / LATERAL / 递归 CTE / GROUPING SETS)需要工具实现支持 — 如果 ogexplain-analyzer 还没实现,相关 query 会 0% 触发。这是设计意图(测工具的覆盖率),不是 GT 错。

## 后续迭代方向

- **v3.1**: 补充更多 ORMs 常见模式(CASE WHEN 链、COALESCE 嵌套、复杂布尔表达式)
- **v3.2**: 加入 explain 输出对比(同 SQL 在 PG / MySQL / openGauss 不同 DB 上的 EXPLAIN 差异)
- **v4.0**: 基于 v3 评估发现的工具弱项规则,反向加权扩充

---

# v3.1 增量(2026-06-21)

v3.1 在 v3 基础上新增 34 条 query(Q160-Q193),总 case 数:193。

## 三大新场景

### 1. 分区索引 / 全局索引(12 个, Q160-Q171)

| 索引类型 | QID |
|----------|-----|
| 局部分区索引 | Q160 |
| 跨分区查询(无全局索引) | Q161 |
| Index-only scan(covering) | Q162 |
| Bitmap OR | Q163 |
| 表达式索引(LOWER) | Q164 |
| 复合索引 leading | Q165 |
| 复合索引非 leading | Q166 |
| 部分索引(WHERE 谓词) | Q167 |
| HASH 函数索引 | Q168 |
| 复合索引末列 | Q169 |
| 全局 + 分区剪枝 | Q170 |
| Index + heap fetch | Q171 |

### 2. UPDATE SET 多字段带子查询(12 个, Q172-Q183)

| UPDATE 模式 | QID |
|------------|-----|
| 单字段 SET + 标量子查询 | Q172 |
| 多字段 SET + 多子查询 | Q173 |
| 嵌套相关子查询(3 层) | Q174 |
| UPDATE FROM + 聚合 | Q175 |
| UPDATE WHERE NOT IN | Q176 |
| UPDATE WHERE EXISTS | Q177 |
| UPDATE WITH CTE | Q178 |
| UPDATE 分区表 | Q179 |
| UPDATE 多字段 FROM JOIN | Q180 |
| UPDATE RETURNING | Q181 |
| UPDATE CASE WHEN | Q182 |
| UPDATE RECURSIVE CTE | Q183 |

### 3. 多层嵌套视图不下推(10 个, Q184-Q193)

| 视图模式 | 类别 | QID |
|---------|------|-----|
| 1 层 + WHERE | 正例(下推) | Q184 |
| 2 层嵌套 | 正例 | Q185 |
| 3 层嵌套 | 正例 | Q186 |
| GROUP BY 视图 | 反例 | Q187 |
| UNION 视图 | 正例 | Q188 |
| 标量子查询视图 | 反例 | Q189 |
| 分区表视图 | 反例 | Q190 |
| DISTINCT 视图 | 反例 | Q191 |
| LIMIT 视图 | 反例 | Q192 |
| HAVING 视图 | 反例 | Q193 |

## v3.1 用法

```bash
# 1. run_explain.py 已支持 CREATE DDL(1 行改动,见脚本注释)
#    CREATE INDEX / CREATE VIEW 会被当作 setup,事务回滚时自动清理

python3 scripts/run_explain.py --version v3

# 2. 生成 case JSON
python3 scripts/build_cases.py --version v3

# 3. 评估
python3 evaluate.py --mode live \
    --cases /path/to/ogagila/benchmark/v3/cases/ \
    --ogexplain-binary target/release/ogexplain
```

## 重要 caveat

1. **DDL 依赖**:v3.1 大量 query 含 `CREATE INDEX` / `CREATE VIEW` 块。run_explain.py 已加 1 行支持(`CREATE ` / `CREATE OR REPLACE ` 视为 setup)。事务回滚时索引/视图自动清理,**不会污染**。

2. **case JSON 未生成**:193 个 case 中只有 97 个有 JSON(v2 继承)。其余 96 个需要跑 `run_explain.py --version v3` + `build_cases.py --version v3` 后才有。

3. **视图测试可能需要 DBA 复核**:Q184-Q193 的"正反例"分类是基于 SQL 模式推定的(视图内 GROUP BY → 谓词不下推)。实际 openGauss 优化器可能比预期更聪明(可能下推),也可能更笨(不能下推)。需要 EXPLAIN 跑完后人工 review 决定。
