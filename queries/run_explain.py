#!/usr/bin/env python3
"""
run_explain.py — 一键跑 queries_v1.sql 并保存每条 query 的 EXPLAIN ANALYZE。

用法:
  pip install psycopg2-binary
  python3 run_explain.py --host localhost --port 5432 --db pagila \\
                        --user gaussdb --password Enmo@123 --out ./explains/

设计要点 (v2 修复版):
  - **从 queries_v1.sql 直接解析 SQL body** (按 `-- @id: QXX` 标记切分)
    不再信任 queries_meta.json 里的 `sql` 字段 — 历史 bug 导致它被截断/留空。
    meta 只用于标签 (target_rule / severity / scenario / is_healthy)。
  - **多语句 body 自动拆分**: SET/RESET 当作 setup/teardown, DELETE STATISTICS 在
    openGauss 上没有等价语法故软跳过 (warning, 不算失败), 其余 (SELECT/UPDATE/...)
    取第一条作为 EXPLAIN 目标。
  - 每个 query 仍跑在独立 BEGIN/ROLLBACK 事务里, 副作用不会污染后续。
"""

import argparse
import json
import re
import sys
import time
from pathlib import Path

try:
    import psycopg2
    import psycopg2.extensions
except ImportError:
    print("缺少 psycopg2, 请运行: pip install psycopg2-binary", file=sys.stderr)
    sys.exit(1)


def parse_args():
    p = argparse.ArgumentParser(description="Run queries_v1 against openGauss and save EXPLAIN ANALYZE")
    p.add_argument("--host", default="localhost")
    p.add_argument("--port", default=5432, type=int)
    p.add_argument("--db", default="pagila")
    p.add_argument("--user", default="gaussdb")
    p.add_argument("--password", default="Enmo@123")
    p.add_argument("--meta", default="./queries_meta.json",
                   help="Path to queries_meta.json (provides labels only)")
    p.add_argument("--sql", default=None,
                   help="Path to queries_v1.sql (provides actual SQL bodies). "
                        "Default: same dir as --meta, file 'queries_v1.sql'")
    p.add_argument("--out", default="./explains", help="Output directory")
    p.add_argument("--no-analyze", action="store_true",
                   help="Skip ANALYZE keyword (just EXPLAIN)")
    p.add_argument("--no-rollback", action="store_true",
                   help="DO NOT rollback (DEBUG ONLY — will leave side effects)")
    p.add_argument("--filter", default=None,
                   help="Only run queries matching this regex (e.g. '^Q0[1-9]$')")
    return p.parse_args()


def connect(args):
    conn = psycopg2.connect(
        host=args.host, port=args.port, dbname=args.db,
        user=args.user, password=args.password,
        connect_timeout=10,
    )
    conn.set_isolation_level(psycopg2.extensions.ISOLATION_LEVEL_AUTOCOMMIT)
    return conn


ID_RE   = re.compile(r'^--\s*@id:\s*(Q\d+)\s*$', re.IGNORECASE)
META_RE = re.compile(r'^--\s*@(\w+):\s*(.*)$')


def parse_sql_file(path: Path) -> dict:
    """
    Parse queries_v1.sql into {qid: {target, severity, scenario, body}}.
    Body = everything between this `-- @id:` and the next, after stripping:
      - metadata comment lines (@target / @severity / @scenario)
      - leading section header comments (-- ====, -- [RULE-XXX])
      - trailing comments after the last top-level `;`
    """
    blocks = []
    cur_id = None
    cur_lines = []

    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            m = ID_RE.match(line)
            if m:
                if cur_id is not None:
                    blocks.append((cur_id, cur_lines))
                cur_id = m.group(1)
                cur_lines = []
                continue
            if cur_id is not None:
                cur_lines.append(line)
        if cur_id is not None:
            blocks.append((cur_id, cur_lines))

    queries = {}
    for qid, lines in blocks:
        meta = {}
        body_candidates = []
        for line in lines:
            m = META_RE.match(line)
            if m and m.group(1).lower() in ("target", "severity", "scenario"):
                meta[m.group(1).lower()] = m.group(2).strip()
                continue
            body_candidates.append(line)

        # Strip leading noise: empty lines + section header comments (-- ==..., -- [RULE-...)
        # but PRESERVE inline SQL comments (e.g. SELECT * -- foo).
        started = False
        cleaned = []
        for line in body_candidates:
            stripped = line.strip()
            if not started:
                if stripped == "":
                    continue
                if stripped.startswith("--"):
                    continue
                started = True
            cleaned.append(line)

        # Truncate after the LAST line containing a top-level `;` (drops trailing section comments)
        last_term = -1
        for i, line in enumerate(cleaned):
            if ";" in line:
                last_term = i
        if last_term >= 0:
            cleaned = cleaned[: last_term + 1]
        body = "\n".join(cleaned).strip()

        queries[qid] = {**meta, "body": body}
    return queries


def split_statements(body: str) -> list:
    """
    Split SQL body into individual statements on top-level `;`,
    respecting single quotes ('), double quotes ("), and parentheses.
    """
    stmts = []
    cur = []
    in_squote = in_dquote = False
    paren = 0
    i = 0
    n = len(body)
    while i < n:
        ch = body[i]
        if in_squote:
            cur.append(ch)
            if ch == "'":
                if i + 1 < n and body[i + 1] == "'":   # SQL escape: ''
                    cur.append(body[i + 1])
                    i += 2
                    continue
                in_squote = False
        elif in_dquote:
            cur.append(ch)
            if ch == '"':
                in_dquote = False
        else:
            if ch == "'":
                in_squote = True; cur.append(ch)
            elif ch == '"':
                in_dquote = True; cur.append(ch)
            elif ch == "(":
                paren += 1; cur.append(ch)
            elif ch == ")":
                paren = max(0, paren - 1); cur.append(ch)
            elif ch == ";" and paren == 0:
                stmt = "".join(cur).strip()
                if stmt:
                    stmts.append(stmt)
                cur = []
            else:
                cur.append(ch)
        i += 1
    tail = "".join(cur).strip()
    if tail:
        stmts.append(tail)
    return stmts


# openGauss does NOT support PG's `DELETE STATISTICS table;` syntax.
# (`ALTER TABLE t DELETE STATISTICS ((c1,c2))` only targets multi-col stats.)
# We soft-skip these and let the subsequent SELECT run with current stats.
DELETE_STATS_RE = re.compile(r'^\s*DELETE\s+STATISTICS\s+', re.IGNORECASE)


def classify(stmt: str):
    """
    Return one of:
      ('setup',    stmt)   — run before EXPLAIN, no EXPLAIN prefix
      ('teardown', stmt)   — run after EXPLAIN, no EXPLAIN prefix (moot due to ROLLBACK)
      ('skip',     stmt)   — unsupported in openGauss; record warning, don't run
      ('main',     stmt)   — the statement to EXPLAIN
    """
    upper = stmt.lstrip().upper()
    if DELETE_STATS_RE.match(stmt):
        return ('skip', stmt)
    if upper.startswith("SET "):
        return ('setup', stmt)
    if upper.startswith("RESET "):
        return ('teardown', stmt)
    if upper == "ANALYZE" or upper.startswith("ANALYZE "):
        return ('setup', stmt)
    return ('main', stmt)


def format_explain_output(qid, sql_meta, body, explain_text, warnings, err):
    lines = []
    lines.append(f"-- @id: {qid}")
    if sql_meta.get("target"):
        lines.append(f"-- @target: {sql_meta['target']}")
    if sql_meta.get("severity"):
        lines.append(f"-- @severity: {sql_meta['severity']}")
    if sql_meta.get("scenario"):
        lines.append(f"-- @scenario: {sql_meta['scenario']}")
    if body:
        lines.append(body)
    lines.append("")
    if err:
        lines.append(f"-- FAILED: {err}")
    else:
        lines.append(explain_text.rstrip())
    if warnings:
        lines.append("")
        for w in warnings:
            lines.append(f"-- ⚠ {w}")
    return "\n".join(lines) + "\n"


def run_one(conn, body: str, use_analyze: bool, do_rollback: bool):
    """
    Run a single query block inside a transaction.
    Returns (success, explain_text, error_message, warnings_list).
    """
    stmts = split_statements(body)
    setups, teardowns, mains, skipped = [], [], [], []
    for s in stmts:
        cls, conv = classify(s)
        if cls == 'setup':       setups.append(conv)
        elif cls == 'teardown':  teardowns.append(conv)
        elif cls == 'skip':      skipped.append(conv)
        else:                    mains.append(conv)

    warnings = [f"skipped unsupported in openGauss: {s[:60]!r}" for s in skipped]

    if not mains:
        return (False, "", "no EXPLAINable statement found (body had only setup/skip)", warnings)

    explain_prefix = "EXPLAIN ANALYZE" if use_analyze else "EXPLAIN"
    main_stmt = mains[0]

    cur = conn.cursor()
    cur.execute("BEGIN;")
    try:
        for s in setups:
            try:
                cur.execute(s)
            except Exception as e:
                warnings.append(f"setup failed {s[:40]!r}: {str(e)[:80]}")

        cur.execute(f"{explain_prefix}\n{main_stmt}")
        rows = cur.fetchall()
        explain_text = "\n".join(r[0] for r in rows) if rows else ""

        for s in teardowns:
            try:
                cur.execute(s)
            except Exception:
                pass

        if do_rollback:
            cur.execute("ROLLBACK;")
        else:
            cur.execute("COMMIT;")

        if not explain_text.strip():
            return (False, "", "EXPLAIN returned no rows", warnings)
        return (True, explain_text, "", warnings)

    except Exception as e:
        try:
            cur.execute("ROLLBACK;")
        except Exception:
            pass
        return (False, "", str(e).strip().split("\n")[0][:300], warnings)
    finally:
        cur.close()


def main():
    args = parse_args()

    meta_path = Path(args.meta).resolve()
    sql_path = Path(args.sql).resolve() if args.sql \
               else meta_path.parent / "queries_v1.sql"
    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    if not meta_path.exists():
        print(f"[FAIL] meta not found: {meta_path}", file=sys.stderr)
        sys.exit(2)
    if not sql_path.exists():
        print(f"[FAIL] sql not found: {sql_path}", file=sys.stderr)
        sys.exit(2)

    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)
    meta_by_id = {q["id"]: q for q in meta.get("queries", [])}

    sql_by_id = parse_sql_file(sql_path)

    queries = []
    missing_body = []
    for q in meta.get("queries", []):
        qid = q["id"]
        body = sql_by_id.get(qid, {}).get("body", "")
        if not body:
            missing_body.append(qid)
        queries.append({
            "id": qid,
            "target_rule": q.get("target_rule", ""),
            "severity":    q.get("severity", ""),
            "scenario":    q.get("scenario", ""),
            "has_side_effect": q.get("has_side_effect", False),
            "is_healthy":  q.get("is_healthy", False),
            "body":        body,
            "sql_meta":    sql_by_id.get(qid, {}),
        })

    if missing_body:
        print(f"[warn] no SQL body parsed for: {missing_body}", file=sys.stderr)

    if args.filter:
        pattern = re.compile(args.filter)
        queries = [q for q in queries if pattern.match(q["id"])]

    print(f"[connect] {args.user}@{args.host}:{args.port}/{args.db}", file=sys.stderr)
    print(f"[meta]    {meta_path}", file=sys.stderr)
    print(f"[sql]     {sql_path}  ({len(sql_by_id)} queries parsed)", file=sys.stderr)
    try:
        conn = connect(args)
    except Exception as e:
        print(f"[FAIL] 连接失败: {e}", file=sys.stderr)
        sys.exit(2)

    print(f"[start] {len(queries)} queries → {out_dir}", file=sys.stderr)
    print(f"[mode] {'EXPLAIN ANALYZE' if not args.no_analyze else 'EXPLAIN (no ANALYZE)'}", file=sys.stderr)
    print(f"[rollback] {'OFF (DEBUG)' if args.no_rollback else 'ON'}", file=sys.stderr)

    index = []
    ok = 0
    fail = 0
    warn_count = 0
    t0 = time.time()

    for q in queries:
        qid = q["id"]
        target = q["target_rule"]
        scenario = q["scenario"]
        body = q["body"]

        t1 = time.time()
        if not body:
            success, explain, err, warnings = False, "", "no SQL body parsed from queries_v1.sql", []
        else:
            success, explain, err, warnings = run_one(
                conn, body,
                use_analyze=not args.no_analyze,
                do_rollback=not args.no_rollback,
            )
        dt = time.time() - t1

        explain_path = out_dir / f"{qid}.explain"
        meta_path_out = out_dir / f"{qid}.meta.json"

        content = format_explain_output(
            qid, q.get("sql_meta", {}), body, explain, warnings, err,
        )
        explain_path.write_text(content, encoding="utf-8")

        if success:
            ok += 1
            status = "OK"
            if warnings:
                warn_count += 1
                status = f"OK (with {len(warnings)} warning)"
        else:
            fail += 1
            status = f"FAIL: {err}"

        meta_path_out.write_text(json.dumps({
            "id": qid,
            "target_rule": target,
            "severity": q["severity"],
            "scenario": scenario,
            "has_side_effect": q["has_side_effect"],
            "is_healthy": q["is_healthy"],
            "status": status,
            "warnings": warnings,
            "elapsed_sec": round(dt, 3),
            "explain_file": str(explain_path.name),
        }, indent=2, ensure_ascii=False), encoding="utf-8")

        index.append({
            "id": qid,
            "target_rule": target,
            "status": status,
            "elapsed_sec": round(dt, 3),
            "warnings": warnings,
        })

        marker = "✓" if success else "✗"
        flag = " ⚠" if warnings else ""
        print(f"  [{marker}{flag}] {qid} {target:<14} ({dt:>5.2f}s) {scenario[:60]}", file=sys.stderr)

    conn.close()

    (out_dir / "index.json").write_text(json.dumps({
        "version": "2.0",
        "total": len(queries),
        "ok": ok,
        "fail": fail,
        "warn": warn_count,
        "elapsed_sec": round(time.time() - t0, 2),
        "queries": index,
    }, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\n[done] {ok} ok / {fail} fail / {warn_count} warn / {len(queries)} total in {time.time()-t0:.1f}s",
          file=sys.stderr)
    print(f"[out]  {out_dir}/index.json", file=sys.stderr)

    sys.exit(0 if fail == 0 else 1)


if __name__ == "__main__":
    main()
