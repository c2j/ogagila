#!/usr/bin/env python3
"""
reclassify_issue1.py — 修复 GitHub Issue #1 中 23 个 GT 标签错误的 case。

Issue: https://github.com/c2j/ogagila/issues/1
23 个 case 的 optimizer 已做最优选择或数据规模太小无法触发规则，
但 GT 仍标 is_problematic=true → evaluator 产生 false FN。

修改内容:
  1. is_problematic → false
  2. expected_severity_if_problematic → null
  3. root_causes → 标准 no_real_problem 模板 (保留原 evidence/runtime)
  4. suggested_fixes → []
  5. validation.reclassification_note 记录原因
  6. 同步更新 case_index.json 和 trigger_coverage.md

用法:
  python3 benchmark/scripts/reclassify_issue1.py             # 默认 v2
  python3 benchmark/scripts/reclassify_issue1.py --version v1
  python3 benchmark/scripts/reclassify_issue1.py --version v3 # (若存在)
"""

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime, timezone

SCRIPT_DIR = Path(__file__).resolve().parent
BENCH_DIR = SCRIPT_DIR.parent

RECLASSIFY = {
    # Category A: JOIN-001 — optimizer 选了 Hash/Merge Join, 无 Nested Loop
    "OGEXP-GT-2026-0015": "Optimizer chose Hash Join (×4), not Nested Loop — already optimal join strategy",
    "OGEXP-GT-2026-0016": "Optimizer chose Merge Join, not Nested Loop — already optimal join strategy",
    "OGEXP-GT-2026-0019": "Optimizer chose Merge Join, not Nested Loop — already optimal join strategy",

    # Category B: MEM-001 — 无外部排序 (Index Scan 绕过 / top-N heapsort)
    "OGEXP-GT-2026-0024": "Index Scan avoids sorting entirely — no Sort node, no spill",
    "OGEXP-GT-2026-0025": "top-N heapsort (Memory: 31kB) — in-memory sort, not external spill",
    "OGEXP-GT-2026-0026": "top-N heapsort (Memory: 27kB) — in-memory sort, not external spill",
    "OGEXP-GT-2026-0027": "top-N heapsort (Memory: 34kB) — in-memory sort, not external spill",

    # Category C: MEM-004 — 内存使用远低于阈值
    "OGEXP-GT-2026-0028": "Memory usage (418kB, 821kB) far below MEM-004 threshold (102400kB) — Pagila dataset too small",
    "OGEXP-GT-2026-0029": "Memory usage far below MEM-004 threshold (102400kB) — Pagila dataset too small",
    "OGEXP-GT-2026-0030": "Memory usage (883kB, 492kB, 308kB) far below MEM-004 threshold (102400kB) — Pagila dataset too small",

    # Category D: AGG-001 — 已是最优聚合策略
    "OGEXP-GT-2026-0071": "HashAggregate already used (enable_sort=off worked) — already optimal",
    "OGEXP-GT-2026-0072": "GroupAggregate forced but only 2 staff groups — data too small for this rule",

    # Category E: REW-001 — IN 列表已被 optimizer 改写
    "OGEXP-GT-2026-0066": "IN list converted to =ANY(array) with Index Only Scan — optimizer already rewrote it",
    "OGEXP-GT-2026-0067": "IN list converted to Hash Semi Join with VALUES — optimizer already rewrote it",

    # Category F: SORT-003 — 无重复排序
    "OGEXP-GT-2026-0031": "Only 1 Sort node (quicksort, 32kB) with different keys — no duplicate sort",
    "OGEXP-GT-2026-0032": "Only 1 Sort node — UNION ALL does not produce duplicate sort",
    "OGEXP-GT-2026-0033": "Only 1 Sort node — no parent-child duplicate sort key",

    # Category G: GEN-001 — 计划深度太浅
    "OGEXP-GT-2026-0081": "Plan depth ~4, GEN-001 threshold >10 — optimizer flattened nested queries to Semi Joins",
    "OGEXP-GT-2026-0082": "Plan depth ~3-4, GEN-001 threshold >10 — optimizer flattened nested queries to Semi Joins",

    # Category H: TYPE-001 — 隐式转换已被正确处理
    "OGEXP-GT-2026-0044": "Implicit cast handled correctly — optimizer used Index Scan (customer_id = 42)",
    "OGEXP-GT-2026-0045": "Implicit cast handled correctly — optimizer used Index Scan",
    "OGEXP-GT-2026-0046": "Implicit cast handled correctly — optimizer used Index Scan",
    "OGEXP-GT-2026-0047": "Implicit cast handled correctly — optimizer used Index Scan",
}

assert len(RECLASSIFY) == 23, f"Expected 23 cases, got {len(RECLASSIFY)}"


def reclassify_case(cases_dir: Path, case_id: str, reason: str):
    case_path = cases_dir / f"{case_id}.json"
    if not case_path.exists():
        print(f"  [MISSING] {case_path}")
        return None

    data = json.loads(case_path.read_text(encoding="utf-8"))
    gt = data["ground_truth"]
    runtime = data["input"].get("plan_actual_runtime_ms", 0)

    gt["is_problematic"] = False
    gt["expected_severity_if_problematic"] = None
    gt["root_causes"] = [{
        "cause_id": "RC-1",
        "category": "no_real_problem",
        "severity": "info",
        "description": reason,
        "evidence": gt["root_causes"][0].get("evidence", "(no evidence)") if gt["root_causes"] else "(no evidence)",
        "verification_method": "runtime_trace",
        "verification_detail": f"EXPLAIN ANALYZE runtime: {runtime}ms",
        "verified_by": ["reclassified_per_issue_1"],
    }]
    gt["suggested_fixes"] = []
    data["validation"]["reclassification_note"] = (
        f"Issue #1 reclassification ({datetime.now(timezone.utc).strftime('%Y-%m-%d')}): "
        f"{reason}"
    )
    data["updated_at"] = datetime.now(timezone.utc).isoformat()

    case_path.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")
    return data


def update_index_and_coverage(version_dir: Path, cases_dir: Path):
    index_path = version_dir / "case_index.json"
    coverage_path = version_dir / "trigger_coverage.md"

    if index_path.exists():
        index = json.loads(index_path.read_text(encoding="utf-8"))
        for entry in index["cases"]:
            if entry["case_id"] in RECLASSIFY:
                entry["is_healthy"] = True
        index["updated_at"] = datetime.now(timezone.utc).isoformat()
        index_path.write_text(json.dumps(index, indent=2, ensure_ascii=False), encoding="utf-8")


    trigger_summary = {}
    case_count = 0
    for cf in sorted(cases_dir.glob("OGEXP-GT-*.json")):
        d = json.loads(cf.read_text(encoding="utf-8"))
        case_count += 1
        rule = d["_auto_eval"]["target_rule_designed"]
        trigger_summary.setdefault(rule, {"total": 0, "triggered": 0, "skipped": 0})
        trigger_summary[rule]["total"] += 1
        if d["ground_truth"]["is_problematic"]:
            trigger_summary[rule]["triggered"] += 1
        else:
            trigger_summary[rule]["skipped"] += 1

    lines = [
        "# Trigger Coverage Report",
        "",
        f"**Generated:** {datetime.now(timezone.utc).isoformat()}",
        f"**Source:** ogagila repo + queries_meta.json",
        f"**Note:** 23 cases reclassified per Issue #1 — rules that cannot physically trigger on Pagila data",
        f"**Total cases:** {case_count}",
        "",
        "## Per-rule trigger coverage",
        "",
        "| Rule | Designed | Actually Triggered | Skipped (healthy / cannot trigger) | Trigger Rate |",
        "|------|----------|--------------------|------------------------------------|--------------|",
    ]
    for rule in sorted(trigger_summary.keys()):
        s = trigger_summary[rule]
        rate = f"{100 * s['triggered'] / s['total']:.0f}%" if s["total"] else "—"
        lines.append(f"| {rule} | {s['total']} | {s['triggered']} | {s['skipped']} | {rate} |")

    lines += [
        "",
        "## Notes",
        "",
        "- **Skipped** = case is either healthy (not problematic) or the rule's condition cannot physically manifest on Pagila (~16K rows, centralized).",
        "- **Issue #1 reclassification (2026-06-21)**: 23 cases (JOIN-001/MEM-001/MEM-004/AGG-001/REW-001/SORT-003/GEN-001/TYPE-001) where the optimizer already chose the optimal strategy or the dataset is too small. These are now `is_problematic: false`.",
        "- For healthy cases (target_rule = NONE), no trigger expected — they are 'true negatives'.",
        "",
    ]
    coverage_path.write_text('\n'.join(lines), encoding="utf-8")


def main():
    p = argparse.ArgumentParser(
        description="Reclassify 23 GT-label-wrong cases per GitHub Issue #1"
    )
    p.add_argument("--version", "-V", default="v2",
                   help="Version dir under benchmark/ (default: v2). "
                        "Processes benchmark/<version>/cases/.")
    args = p.parse_args()

    version_dir = BENCH_DIR / args.version
    cases_dir = version_dir / "cases"

    if not cases_dir.exists():
        sys.exit(f"[ERROR] {cases_dir} does not exist. "
                 f"Version '{args.version}' has no cases/ directory. "
                 f"Run build_cases.py --version {args.version} first.")

    print(f"[reclassify] Version: {args.version}")
    print(f"[reclassify] Cases dir: {cases_dir}")
    print(f"[reclassify] Processing {len(RECLASSIFY)} cases")

    ok = fail = 0
    for case_id, reason in RECLASSIFY.items():
        result = reclassify_case(cases_dir, case_id, reason)
        if result:
            ok += 1
        else:
            fail += 1

    print(f"\n[reclassify] {ok} updated, {fail} failed (out of {len(RECLASSIFY)})")

    if ok > 0:
        update_index_and_coverage(version_dir, cases_dir)
        print(f"[reclassify] {version_dir}/case_index.json + trigger_coverage.md updated")


if __name__ == "__main__":
    main()
