#!/usr/bin/env bash
# Phase 0 QA — Q0.5 并发原子领取（K1 契约）
# 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §5.3.1 K1
#
# 验证要点：两个 worker 并发领取同一批次时，必须只有一个成功。
# 用法：bash qa-phase0-concurrent.sh [fixed|naive]   默认 fixed
# K1 的两层防御缺一不可（用 naive 模式可复现缺陷）：
#   1) 子查询 FOR UPDATE SKIP LOCKED  -> 并发者立即跳过被锁行，不阻塞
#   2) 外层 status='PENDING'          -> 锁释放后的复查，防止覆盖已领取任务
# 省略第 2 层时实测双重领取：两会话均返回同一 task_id，终态 attempt=2。
set -uo pipefail

CONTAINER=${CONTAINER:-pagila}
RUN_ID=R_QA_CLAIM
MODE=${1:-fixed}

gs() { docker exec "$CONTAINER" gsql-pagila "$@"; }

if [ "$MODE" = "fixed" ]; then
  GUARD="status = 'PENDING' AND"
  LOCK="FOR UPDATE SKIP LOCKED"
else
  GUARD=""
  LOCK=""
fi

claim_sql() {
  cat <<SQL
UPDATE dw.etl_task_queue
   SET status='CLAIMED', claimed_by='$1', claimed_at=now(), attempt=attempt+1
 WHERE $GUARD task_id = (SELECT task_id FROM dw.etl_task_queue
                          WHERE run_id='$RUN_ID' AND status='PENDING'
                          ORDER BY seq_no LIMIT 1 $LOCK)
RETURNING task_id, claimed_by;
SQL
}

gs -c "DELETE FROM dw.etl_task_queue WHERE run_id='$RUN_ID';
       INSERT INTO dw.etl_task_queue(run_id,step_name,seq_no,sql_text)
       VALUES ('$RUN_ID','s1',1,'SELECT 1');" >/dev/null 2>&1

{ echo "BEGIN;"; claim_sql A; echo "SELECT pg_sleep(4); COMMIT;"; } > /tmp/qa_claim_a.sql
claim_sql B > /tmp/qa_claim_b.sql
docker cp /tmp/qa_claim_a.sql "$CONTAINER":/tmp/ >/dev/null 2>&1
docker cp /tmp/qa_claim_b.sql "$CONTAINER":/tmp/ >/dev/null 2>&1

( gs -f /tmp/qa_claim_a.sql 2>&1 | sed 's/^/[A] /' ) &
sleep 1
( gs -f /tmp/qa_claim_b.sql 2>&1 | sed 's/^/[B] /' ) &
wait

echo "=== Q0.5 result (mode=$MODE) ==="
gs -t -c "SELECT CASE WHEN count(*)=1 AND max(attempt)=1 AND max(claimed_by)='A'
                      THEN 'Q0.5 PASS (single claim by A, attempt=1)'
                      ELSE 'Q0.5 FAIL (attempt=' || max(attempt)
                           || ', claimed_by=' || max(claimed_by) || ')' END
            FROM dw.etl_task_queue WHERE run_id='$RUN_ID';"
gs -c "DELETE FROM dw.etl_task_queue WHERE run_id='$RUN_ID';" >/dev/null 2>&1
