# Changelog: v2 → v3

**生成时间:** 2026-06-21
**修改方式:** 在 v2 基础上追加 62 条新 query,扩展数据集
**SQL 源:** `v3/queries.sql`(49,119 字符,159 条 query)
**元数据:** `v3/queries_meta.json`(159 条 entry)

---

## v3 增量概要

v3 = v2 (97 cases) + v3 新增 (62 cases) = **159 cases**

| 类别 | 新增 | 说明 |
|------|------|------|
| Block 1: WINDOW 函数 | 8 | ROW_NUMBER / RANK / LAG / NTILE / 累计 / 移动平均 |
| Block 2: CTE 进阶 | 8 | 多 CTE / 递归 CTE / 嵌套 CTE |
| Block 3: LATERAL JOIN | 3 | TOP-N per group / 子查询展开 |
| Block 4: Set Operations | 4 | UNION / INTERSECT / EXCEPT / 混合 |
| Block 5: 子查询模式 | 6 | 标量 / 相关 / EXISTS / 派生表 |
| Block 6: 聚合进阶 | 5 | GROUPING SETS / CUBE / ROLLUP / FILTER / PERCENTILE |
| Block 7: 类型转换 | 3 | WHERE / JOIN 中隐式 cast |
| Block 8: 边界 case | 6 | 空结果 / 单行 / NULL / DISTINCT ON / 自连接 / 分页 |
| Block 9: 真实场景 | 6 | N+1 / 时间序列 / Top-N / 漏斗 / 队列 / 全文搜索 |
| Block 10: 0% 规则补强 | 10 | GEN-001 / MEM-004 / PUSH-001 / SORT-003 / SUBQ-001 / VEC-001 / SKEW-001 |
| Block 11: 健康 case 补强 | 3 | 简单聚合 / 索引等值 / 简单 TOP-N |
| **合计** | **62** | |

---

## v3 解决的具体覆盖空白

| 空白 | v2 状态 | v3 解决方式 |
|------|--------|-------------|
| WINDOW 函数 | 0 cases | +8 cases (Q98-Q105) |
| LATERAL | 0 cases | +3 cases (Q114-Q116) |
| 递归 CTE | 0 cases | +2 cases (Q109, Q110) |
| INTERSECT / EXCEPT | 0 cases | +2 cases (Q118, Q119) |
| GROUPING SETS / CUBE / ROLLUP | 0 cases | +3 cases (Q127-Q129) |
| FILTER 子句 | 0 cases | +1 case (Q130) |
| EXISTS / NOT EXISTS | 0 cases | +2 cases (Q122, Q123) |
| DISTINCT ON | 0 cases | +1 case (Q137) |
| 自连接 | 1 case | +1 case (Q138) |
| N+1 模式 | 0 cases | +1 case (Q141) |
| 漏斗 / 队列分析 | 0 cases | +2 cases (Q144, Q145) |
| 0% 触发的 GEN-001 补强 | 0 triggered | +6 cases (Q98-100, 108, 137, 147) |
| 0% 触发的 MEM-004 补强 | 0 triggered | +2 cases (Q131, Q148) |
| 0% 触发的 PUSH-001 补强 | 0 triggered | +2 cases (Q149, Q154) |
| 0% 触发的 SORT-003 补强 | 0 triggered | +1 case (Q150) |
| 0% 触发的 SUBQ-001 补强 | 0 triggered | +8 cases (Q111, 115, 118-119, 121-124, 126, 141, 151) |
| 健康 case 补强 | 15 | +5 cases (Q135, 136, 157-159) |

---

## 规则覆盖统计(v3 期望)

| 规则 | v2 触发率 | v3 期望 |
|------|----------|---------|
| TYPE-004 | 100% | 100% |
| SUBQ-006 | 100% | 100% |
| SCAN-001 | 0%(GT 错修后 78.6%) | 0%(LIMIT 设计边界) |
| SCAN-004 | 0%(GT 错修后 55.2%) | 更高(more WHERE 模式) |
| EST-001 | 0%(openGauss 跳过 DELETE) | 0%(v3 也用 DELETE) |
| **GEN-001** | 0% | **期望 >50%** (8 个 WINDOW + 6 个 CTE + 4 个 SET 等) |
| **SUBQ-001** | 0% | **期望 >30%** (8 个新 SUBQ case) |
| **AGG-001** | 未测 | **新增测试** (4 个 GROUPING/ROLLUP) |
| **PUSH-001** | 0% | **期望 >20%** (2 个新 case) |
| **SORT-003** | 0% | **新增测试** (1 个新 case) |
| **VEC-001** | 66% | 保持 |
| **SKEW-001** | 100% | 保持 |

---

## v3 是否需要 GT 修正?

**可能需要。** v3 用了 v2 一样的 build_cases.py 自动生成 case JSON。但 v3 引入的新 SQL 模式(WINDOW / LATERAL / 递归 CTE 等)build_cases.py 可能没正确识别对应的 ogexplain 规则(因为 `RULE_TO_CAUSE_CATEGORY` 里没这些 mapping)。

**建议流程**:
1. 跑 `build_cases.py --version v3` 生成 v3 baseline case
2. 跑 `run_explain.py --version v3` 收集真实 EXPLAIN
3. 用 evaluate.py 跑评估
4. 对 0% 触发的规则,人工 review case JSON 决定是工具 bug 还是 GT 错
5. 必要时更新 `RULE_TO_CAUSE_CATEGORY` / `DEFAULT_FIX_TEMPLATES` 反映新规则
6. v3.1 用 apply_v2_fixes.py 同款脚本做修复

---

## v3 用法

```bash
# 1. Stage A: 跑 EXPLAIN(需要 ogagila 容器在跑)
python3 scripts/run_explain.py --version v3

# 2. Stage B: 生成 baseline case
python3 scripts/build_cases.py --version v3

# 3. (可选) 跑评估
python3 evaluate.py --mode live \
    --cases /path/to/ogagila/benchmark/v3/cases/ \
    --ogexplain-binary target/release/ogexplain
```

---

## 兼容性

- v3 case JSON 的 schema 与 v2 兼容(都用同一份 `groundtruth.schema.json`)
- v3 case 编号从 OGEXP-GT-2026-0001 到 OGEXP-GT-2026-0159(连续)
- v2 的 97 个 case 在 v3 中**编号不变**(`0001-0097`)
- v3 新增 62 个 case 编号 `0098-0159`
- 外部工具(ogexplain-analyzer)指向 v3/cases/ 即可评估全部 159 个 case

---

# v3.1 增量(2026-06-21)

相比 v3,新增 **34 条 query** (Q160-Q193),覆盖三大生产场景:

| 类别 | 数量 | QID |
|------|------|-----|
| **Block 12: 分区索引 / 全局索引** | 12 | Q160-Q171 |
| **Block 13: UPDATE SET 多字段带子查询** | 12 | Q172-Q183 |
| **Block 14: 多层嵌套视图不下推** | 10 | Q184-Q193 |

## Block 12: 分区索引 / 全局索引(Q160-Q171)

测试本地/全局索引、复合索引、位图扫描、表达式索引、部分索引、HASH 索引:

| QID | 模式 | 目标规则 | 预期行为 |
|-----|------|---------|----------|
| Q160 | 局部分区索引 seek | PART-001 | 单分区索引,理想下推 |
| Q161 | 跨分区 customer_id 查询 | SCAN-004 | 无全局索引,7 分区都可能走 |
| Q162 | Index-only scan(covering) | SCAN-004 | INCLUDE 子句理想 |
| Q163 | Bitmap OR scan | GEN-001 | 多条件 OR 触发 bitmap |
| Q164 | 表达式索引 LOWER | SCAN-004 | 无表达式索引,全表扫 |
| Q165 | 复合索引 leading column | PART-001 | 命中(customer_id, payment_date) |
| Q166 | 复合索引非 leading | SCAN-004 | 只用 payment_date,索引失效 |
| Q167 | 部分索引(带 WHERE) | SCAN-004 | amount > 5 的部分索引 |
| Q168 | HASH 函数索引 | SCAN-004 | HASHTEXT 包装,无索引 |
| Q169 | 复合索引仅末列 | SCAN-004 | (title, year, rate) 只用 rate |
| Q170 | 全局索引 + 分区剪枝 | PART-001 | 组合场景 |
| Q171 | Index + heap fetch | GEN-001 | 普通索引,非 covering |

## Block 13: UPDATE SET 多字段带子查询(Q172-Q183)

覆盖各种 UPDATE 复杂场景:

| QID | 模式 | 目标规则 |
|-----|------|---------|
| Q172 | UPDATE SET col = 标量子查询 | SUBQ-001 |
| Q173 | UPDATE SET 多字段 + 多子查询 | SUBQ-001 |
| Q174 | UPDATE 嵌套相关子查询(3 层) | SUBQ-001 |
| Q175 | UPDATE FROM + 聚合子查询 | SUBQ-001 |
| Q176 | UPDATE WHERE NOT IN 子查询 | SUBQ-001 |
| Q177 | UPDATE WHERE EXISTS 相关子查询 | SUBQ-001 |
| Q178 | UPDATE WITH CTE | SUBQ-001 |
| Q179 | UPDATE 分区表(单分区) | PART-001 |
| Q180 | UPDATE 多字段 FROM JOIN | GEN-001 |
| Q181 | UPDATE ... RETURNING | GEN-001 |
| Q182 | UPDATE SET with CASE WHEN | GEN-001 |
| Q183 | UPDATE WITH RECURSIVE CTE | SUBQ-001 |

## Block 14: 多层嵌套视图不下推(Q184-Q193)

正例(下推成功):
- Q184: 1 层视图 + WHERE(正例)
- Q185: 2 层嵌套视图(测试下推)
- Q186: 3 层嵌套视图(深度测试)
- Q188: 视图内 UNION(正例,下推到每个分支)

反例(下推失败):
- Q187: 视图内 GROUP BY(谓词无法下推)
- Q189: 视图内标量子查询(反例)
- Q190: 视图套分区表(反例,全分区扫)
- Q191: 视图内 DISTINCT(反例)
- Q192: 视图内 LIMIT(反例)
- Q193: 视图内 HAVING(反例)

## v3.1 关键改动

### `run_explain.py` 加了 1 行 DDL 支持

```python
# 原逻辑
if upper.startswith("SET "):
    return ('setup', stmt)

# v3.1 新增
if upper.startswith("SET "):
    return ('setup', stmt)
if upper.startswith("CREATE ") or upper.startswith("CREATE OR REPLACE "):
    return ('setup', stmt)
```

这样 `CREATE INDEX` / `CREATE VIEW` / `CREATE OR REPLACE VIEW` 都被当作 setup,在事务里执行(随 ROLLBACK 自动清理)。

### v3.1 case JSON 仍未生成

v3/cases/ 当前只有 v2 继承的 97 个 case。新增 96 个 case(Q98-Q193)需要先跑:
```bash
python3 scripts/run_explain.py --version v3
python3 scripts/build_cases.py --version v3
```

### v3.1 预期评估提升

| 指标 | v3 预期 | v3.1 预期 | 提升 |
|------|---------|-----------|------|
| 总 case | 159 | 193 | +34 |
| 索引相关 case | ~25 | 37 | +12 |
| UPDATE 复杂 case | 2 | 14 | +12 |
| 视图 case | 0 | 10 | +10 |
| PUSH 规则 case | 5 | 15 | +10 |

