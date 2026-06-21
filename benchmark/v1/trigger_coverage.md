# Trigger Coverage Report

**Generated:** 2026-06-21T11:55:08.528717+00:00
**Source:** ogagila repo + queries_meta.json
**Note:** 23 cases reclassified per Issue #1 — rules that cannot physically trigger on Pagila data
**Total cases:** 97

## Per-rule trigger coverage

| Rule | Designed | Actually Triggered | Skipped (healthy / cannot trigger) | Trigger Rate |
|------|----------|--------------------|------------------------------------|--------------|
| AGG-001 | 2 | 0 | 2 | 0% |
| AGG-002 | 2 | 2 | 0 | 100% |
| DIST-001 | 2 | 2 | 0 | 100% |
| EST-001 | 4 | 4 | 0 | 100% |
| EST-004 | 3 | 3 | 0 | 100% |
| GEN-001 | 2 | 0 | 2 | 0% |
| JOIN-001 | 5 | 2 | 3 | 40% |
| JOIN-002 | 4 | 4 | 0 | 100% |
| MEM-001 | 4 | 0 | 4 | 0% |
| MEM-004 | 3 | 0 | 3 | 0% |
| NET-001 | 3 | 3 | 0 | 100% |
| NONE | 15 | 0 | 15 | 0% |
| PART-001 | 4 | 4 | 0 | 100% |
| PUSH-001 | 3 | 3 | 0 | 100% |
| PUSH-002 | 3 | 3 | 0 | 100% |
| REW-001 | 2 | 0 | 2 | 0% |
| SCAN-001 | 8 | 8 | 0 | 100% |
| SCAN-004 | 6 | 6 | 0 | 100% |
| SKEW-001 | 2 | 2 | 0 | 100% |
| SORT-003 | 3 | 0 | 3 | 0% |
| STATS-001 | 2 | 2 | 0 | 100% |
| SUBQ-001 | 3 | 3 | 0 | 100% |
| SUBQ-006 | 2 | 2 | 0 | 100% |
| TYPE-001 | 4 | 0 | 4 | 0% |
| TYPE-004 | 3 | 3 | 0 | 100% |
| VEC-001 | 3 | 3 | 0 | 100% |

## Notes

- **Skipped** = case is either healthy (not problematic) or the rule's condition cannot physically manifest on Pagila (~16K rows, centralized).
- **Issue #1 reclassification (2026-06-21)**: 23 cases (JOIN-001/MEM-001/MEM-004/AGG-001/REW-001/SORT-003/GEN-001/TYPE-001) where the optimizer already chose the optimal strategy or the dataset is too small. These are now `is_problematic: false`.
- For healthy cases (target_rule = NONE), no trigger expected — they are 'true negatives'.
