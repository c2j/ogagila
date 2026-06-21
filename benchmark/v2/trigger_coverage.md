# Trigger Coverage Report — v2

**Generated:** 2026-06-20T23:13:46.135336+00:00
**Source:** ogagila repo + queries_meta.json
**Total cases:** 97 (82 problematic + 15 healthy)
**GT fixes from v1 → v2:** 27 cases reclassified (see CHANGELOG_v1_to_v2.md)

## Per-rule trigger coverage (v2)

| Rule | Designed (v2) | Actually Triggered | Notes |
|------|----------------|--------------------|-------|
| AGG-001 | 2 | 2 |  |
| AGG-002 | 2 | 2 |  |
| DIST-001 | 2 | 0 | 2 cases GT expected but EXPLAIN didn't show |
| EST-001 | 4 | 0 | 4 cases GT expected but EXPLAIN didn't show |
| EST-004 | 3 | 0 | 3 cases GT expected but EXPLAIN didn't show |
| GEN-001 | 2 | 0 | 2 cases GT expected but EXPLAIN didn't show |
| JOIN-001 | 5 | 3 | 2 cases GT expected but EXPLAIN didn't show |
| JOIN-002 | 4 | 4 |  |
| MEM-001 | 4 | 3 | 1 cases GT expected but EXPLAIN didn't show |
| MEM-004 | 3 | 0 | 3 cases GT expected but EXPLAIN didn't show |
| NONE (healthy) | 15 | 0 | 15 cases where no rule should trigger |
| PART-001 | 4 | 4 |  |
| PUSH-001 | 3 | 0 | 3 cases GT expected but EXPLAIN didn't show |
| PUSH-002 | 3 | 2 | 1 cases GT expected but EXPLAIN didn't show |
| REW-001 | 2 | 2 |  |
| SCAN-001 | 4 | 8 | co-finds from 4 multi-root-cause cases |
| SCAN-004 | 13 | 6 | 7 cases GT expected but EXPLAIN didn't show |
| SKEW-001 | 2 | 2 |  |
| SORT-003 | 3 | 0 | 3 cases GT expected but EXPLAIN didn't show |
| STATS-001 | 2 | 0 | 2 cases GT expected but EXPLAIN didn't show |
| SUBQ-001 | 3 | 0 | 3 cases GT expected but EXPLAIN didn't show |
| SUBQ-006 | 2 | 2 |  |
| TYPE-001 | 4 | 4 |  |
| TYPE-004 | 3 | 3 |  |
| VEC-001 | 3 | 2 | 1 cases GT expected but EXPLAIN didn't show |

## v1 → v2 关键变化

- **SCAN-001**: v1 8 cases → v2 4 cases(3 个错分类转 SCAN-004 + 2 个 NET-001 转 SCAN-001,净变 -4)
- **SCAN-004**: v1 6 cases → v2 13 cases(+6: 3 个 SCAN-001 + 1 个 NET-001 + 2 个 co-finding)
- **NET-001**: v1 3 cases → v2 0 cases(单节点不可能,3 个移到 SCAN-001/004)
- **多根因 case**: v2 新增 18 个 case 含 co-finding,详见 CHANGELOG

## Notes

- **Designed** = 案例的主规则(target_rule),不含多根因 co-finding
- **Actually Triggered** = build_cases.py 启发式判断 EXPLAIN 中规则条件是否出现
- 多根因 case 的次要 finding 可能贡献 "Actually Triggered" 但不计入 "Designed"
- 健康 case (`is_healthy: true`) 在 NONE 行单独统计
