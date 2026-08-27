#!/usr/bin/env bash
# Phase 2 — 外部 ETL worker（实现方案 §5.3.1 的执行契约 K1~K10）
#
# 定位：调度"触发在外部、编排在库内"（R4）。本脚本不含任何业务顺序知识 ——
# 步骤顺序与依赖全部由库内 PKG_ORCH 写入 dw.etl_task_queue，worker 只负责
# 领取、以**顶层语句**执行、回写状态、按依赖阻塞、按退出码告警。
#
# 用法：
#   bash etl_worker.sh --run-id R_20260827            # 正常执行
#   bash etl_worker.sh --run-id R_20260827 --dry-run   # 只打印将要执行的语句
#   bash etl_worker.sh --run-id R_20260827 --dop 4      # 设置 SMP 并行度
#
# 退出码（契约 K10）：0 = 全部 SUCCEEDED；非 0 = 存在 FAILED/SKIPPED。
set -uo pipefail

CONTAINER=${CONTAINER:-pagila}
RUN_ID=""
DRY_RUN=0
DOP=${DOP:-0}
STALE_HOURS=${STALE_HOURS:-2}
WORKER_ID="$(hostname)-$$"

while [ $# -gt 0 ]; do
  case "$1" in
    --run-id)  RUN_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --dop)     DOP="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[ -n "$RUN_ID" ] || { echo "--run-id is required" >&2; exit 2; }

gs()  { docker exec "$CONTAINER" gsql-pagila "$@"; }
gst() { docker exec "$CONTAINER" gsql-pagila -t -A -c "$1" 2>/dev/null | tr -d '\r'; }

# 契约 K8：回收僵死任务。worker 可能被 kill 而留下 CLAIMED/RUNNING 的孤儿任务。
gst "UPDATE dw.etl_task_queue SET status='PENDING', claimed_by=NULL, claimed_at=NULL
      WHERE run_id='${RUN_ID}' AND status IN ('CLAIMED','RUNNING')
        AND claimed_at < now() - interval '${STALE_HOURS} hours';" >/dev/null

echo "[worker $WORKER_ID] run_id=$RUN_ID dop=$DOP dry_run=$DRY_RUN"

# dry-run 只做只读枚举，**不领取任务**。早期实现用"领取后回滚 attempt"的方式，
# 结果同一任务被反复领取 -> 无限循环。
if [ "$DRY_RUN" = "1" ]; then
  gs -t -A -c "SELECT task_id || '|' || step_name || '|' || COALESCE(depends_on::text,'-')
                 || '|' || sql_text
                 FROM dw.etl_task_queue WHERE run_id='${RUN_ID}' ORDER BY seq_no;" 2>/dev/null |
  while IFS='|' read -r tid step dep sql; do
    [ -n "$tid" ] || continue
    echo "--- [dry-run] task=$tid step=$step depends_on=$dep ---"
    [ "${DOP}" != "0" ] && echo "SET query_dop = ${DOP};"
    echo "$sql"
  done
  exit 0
fi

# 循环上界是防御性护栏：单个任务最多重试 max_attempt 次，正常不会触及。
ITER=0
MAX_ITER=${MAX_ITER:-1000}

while [ "$ITER" -lt "$MAX_ITER" ]; do
  ITER=$((ITER + 1))

  # 契约 K1：单语句原子领取。两层并发防御缺一不可 ——
  #   FOR UPDATE SKIP LOCKED 让并发 worker 立即跳过被锁行；
  #   外层 status 复查防止锁释放后覆盖已被领取的任务。
  # 契约 K6：FAILED 且 attempt < max_attempt 的任务同样可被重新领取。
  #
  # ⚠️ 必须过滤 gsql 的命令标签：即使用 -t -A，UPDATE ... RETURNING 仍会额外
  # 输出一行 "UPDATE 1"。不过滤会污染字段解析（实测导致 step_name 带上标签）。
  CLAIM=$(gst "UPDATE dw.etl_task_queue q
                  SET status='CLAIMED', claimed_by='${WORKER_ID}',
                      claimed_at=now(), attempt=attempt+1
                WHERE q.status IN ('PENDING','FAILED')
                  AND (q.status='PENDING' OR q.attempt < q.max_attempt)
                  AND q.task_id = (
                        SELECT t.task_id FROM dw.etl_task_queue t
                         WHERE t.run_id='${RUN_ID}'
                           AND (t.status='PENDING'
                                OR (t.status='FAILED' AND t.attempt < t.max_attempt))
                           AND (t.depends_on IS NULL
                                OR t.depends_on IN (SELECT s.seq_no FROM dw.etl_task_queue s
                                                     WHERE s.run_id='${RUN_ID}'
                                                       AND s.status='SUCCEEDED'))
                         ORDER BY t.seq_no LIMIT 1 FOR UPDATE SKIP LOCKED)
              RETURNING q.task_id || '|' || q.step_name;" \
          | grep -E '^[0-9]+\|' | head -1)

  if [ -z "$CLAIM" ]; then
    # 契约 K7：无可领取任务时，若存在终态 FAILED，其下游置 SKIPPED 后收尾。
    gst "UPDATE dw.etl_task_queue SET status='SKIPPED', finished_at=now()
          WHERE run_id='${RUN_ID}' AND status='PENDING'
            AND depends_on IN (SELECT seq_no FROM dw.etl_task_queue
                                WHERE run_id='${RUN_ID}' AND status IN ('FAILED','SKIPPED')
                                  AND (status='SKIPPED' OR attempt >= max_attempt));" >/dev/null
    break
  fi

  TASK_ID="${CLAIM%%|*}"
  STEP="${CLAIM##*|}"
  SQL=$(gst "SELECT sql_text FROM dw.etl_task_queue WHERE task_id=${TASK_ID};")

  gst "UPDATE dw.etl_task_queue SET status='RUNNING', started_at=now()
        WHERE task_id=${TASK_ID};" >/dev/null
  echo "[worker] running task=$TASK_ID step=$STEP"

  # 契约 K2：sql_text 必须作为**顶层语句**执行，不得包在存储过程/匿名块内 ——
  # 否则 openGauss 的"过程内查询不支持 SMP"限制生效，QUEUE 模式的唯一目的落空。
  # 契约 K3：执行前设 query_dop，执行后恢复。SET 与 SQL 在同一会话/事务内，
  # SQL 仍是顶层语句（"顶层"指不在过程体内，而非"必须是首条语句"）。
  TMP="/tmp/etl_task_${TASK_ID}.sql"
  {
    echo "\\set ON_ERROR_STOP 1"
    [ "${DOP}" != "0" ] && echo "SET query_dop = ${DOP};"
    echo "$SQL"
    [ "${DOP}" != "0" ] && echo "RESET query_dop;"
  } > "$TMP"
  docker cp "$TMP" "$CONTAINER":"$TMP" >/dev/null 2>&1

  if OUT=$(gs -f "$TMP" 2>&1); then
    ROWS=$(printf '%s\n' "$OUT" | grep -oE '^(INSERT|DELETE|UPDATE) [0-9]+ ?[0-9]*' \
             | tail -1 | grep -oE '[0-9]+$')
    gst "UPDATE dw.etl_task_queue SET status='SUCCEEDED', finished_at=now(),
            affected_rows=${ROWS:-NULL}, err_code=NULL, err_msg=NULL
          WHERE task_id=${TASK_ID};" >/dev/null
    echo "[worker] task=$TASK_ID SUCCEEDED rows=${ROWS:-?}"
  else
    ERR=$(printf '%s' "$OUT" | tr '\n' ' ' | sed "s/'/''/g" | cut -c1-500)
    gst "UPDATE dw.etl_task_queue SET status='FAILED', finished_at=now(),
            err_code='EXEC', err_msg='${ERR}' WHERE task_id=${TASK_ID};" >/dev/null
    echo "[worker] task=$TASK_ID FAILED: $(printf '%s' "$OUT" | head -3)" >&2
  fi
  rm -f "$TMP"
done

# 契约 K10：退出码供外部监控消费。
SUMMARY=$(gst "SELECT status || '=' || count(*) FROM dw.etl_task_queue
                WHERE run_id='${RUN_ID}' GROUP BY status ORDER BY status;" | paste -sd' ' -)
BAD=$(gst "SELECT count(*) FROM dw.etl_task_queue
            WHERE run_id='${RUN_ID}' AND status IN ('FAILED','SKIPPED');")
echo "[worker $WORKER_ID] done: ${SUMMARY:-(empty)}"

if [ "${BAD:-0}" != "0" ]; then
  echo "[worker] $BAD task(s) FAILED/SKIPPED -> exit 1" >&2
  exit 1
fi
exit 0
