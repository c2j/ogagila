# Trigger Coverage Report — v3.1

**Generated:** 2026-06-21
**Source:** ogagila repo + queries_meta.json
**Total cases:** 193 (173 problematic + 20 healthy)
**v3 baseline:** 159 cases (Q01-Q159)
**v3.1 增量:** 34 cases (Q160-Q193),见 `CHANGELOG_v2_to_v3.md` 末尾

## 状态说明

**v3.1 baseline 状态**:v3/cases/ 包含 v2 的 97 个 case(OGEXP-GT-2026-0001.json 到 0097.json)。新增的 96 个 case(Q98-Q193)**尚未生成**,需运行 `run_explain.py --version v3` + `build_cases.py --version v3` 后才有数据。

## v3.1 预期 per-rule 触发覆盖

| Rule | v3.1 Designed | 预期 Actually Triggered | 备注 |
|------|---------------|--------------------------|------|
| AGG-001 | 6 | 4 | |
| AGG-002 | 3 | 3 | |
| DIST-001 | 2 | 0 | 单节点不可能 |
| EST-001 | 4 | 0 | openGauss 跳过 DELETE |
| EST-004 | 3 | 0 | openGauss 跳过 DELETE |
| GEN-001 | 38 | 20+ | 大量 WINDOW/CTE/VIEW case |
| JOIN-001 | 6 | 4 | |
| JOIN-002 | 4 | 4 | |
| MEM-001 | 4 | 3 | |
| MEM-004 | 5 | 2 | |
| NET-001 | 0 | 0 | |
| PART-001 | 8 | 6 | 新增 Q160/Q170/Q179 |
| PUSH-001 | 15 | 8+ | **v3.1 大幅扩展**(Q187/189/190/191/192/193 视图不下推) |
| PUSH-002 | 4 | 3 | |
| REW-001 | 2 | 2 | |
| SCAN-001 | 4 | 4 | |
| SCAN-004 | 23 | 15+ | **v3.1 大幅扩展**(Q164/166/167/168/169 索引) |
| SKEW-001 | 3 | 3 | |
| SORT-003 | 4 | 1 | |
| STATS-001 | 2 | 0 | |
| SUBQ-001 | 24 | 12+ | **v3.1 大幅扩展**(Q172-178/183 UPDATE+子查询) |
| SUBQ-006 | 2 | 2 | |
| TYPE-001 | 7 | 6 | |
| TYPE-004 | 4 | 4 | |
| VEC-001 | 4 | 3 | |
| **NONE** | 20 | 0 | 健康 case |

## v3 → v3.1 覆盖提升

| 指标 | v3 | v3.1 | 提升 |
|------|----|----|------|
| 总 case | 159 | 193 | +34 |
| 索引相关 case(SCAN-004) | 11 | 23 | +12 |
| UPDATE 复杂 case | 2 | 14 | +12 |
| 视图 case(PUSH-001) | 5 | 15 | +10 |
| PUSH-001 总 case | 5 | 15 | +10 |
| SUBQ-001 总 case | 11 | 24 | +13 |
| GEN-001 总 case | 27 | 38 | +11 |

## 评估前置条件

- 跑 `python3 scripts/run_explain.py --version v3` 收集真实 EXPLAIN
- 跑 `python3 scripts/build_cases.py --version v3` 生成 case JSON
- 必要时用 v3.1 修复脚本(类似 apply_v2_fixes.py)修正 GT

## v3.1 caveats

1. **CREATE DDL 支持**:run_explain.py 已加 `CREATE ` / `CREATE OR REPLACE ` 视为 setup
2. **DDL 副作用**:CREATE INDEX/VIEW 在事务里执行,ROLLBACK 时自动清理,**不污染**容器
3. **视图 pushdown 测试**:Q184-Q193 的"正反例"分类基于 SQL 模式推定,需要 EXPLAIN 跑完后人工 review
