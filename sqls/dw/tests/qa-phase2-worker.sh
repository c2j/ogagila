#!/usr/bin/env bash
# Phase 2 QA — worker 失败路径契约验收（K6 重试 / K7 依赖阻塞 / K8 僵死回收 / K10 退出码）
#
# 前置：PKG_ORCH 与 etl_worker.sh 已部署。
# 判定：所有 W-* 行必须为 PASS。
#
# 正常路径（K1/K2/K9）由 qa-phase2-orch.sql 与 worker 正常执行覆盖，本脚本只测失败路径。
set -uo pipefail

CONTAINER=${CONTAINER:-pagila}
WORKER="$(cd "$(dirname "$0")/../scripts" && pwd)/etl_worker.sh"
gst() { docker exec "$CONTAINER" gsql-pagila -t -A -c "$1" 2>/dev/null | tr -d '\r'; }
pass_fail() { if [ "$1" = "$2" ]; then echo "  $3 PASS"; else echo "  $3 FAIL (got=$1 want=$2)"; fi; }

echo "===== W-1  K7 依赖阻塞 + K10 退出码 ====="
gst "DELETE FROM dw.etl_task_queue WHERE run_id='R_QAW1';
     INSERT INTO dw.etl_task_queue(run_id,step_name,seq_no,depends_on,sql_text,max_attempt) VALUES
       ('R_QAW1','ok_step',   1, NULL, 'SELECT 1;', 1),
       ('R_QAW1','fail_step', 2, 1,    'SELECT 1/0;', 1),
       ('R_QAW1','down_step', 3, 2,    'SELECT 1;', 1);" >/dev/null
bash "$WORKER" --run-id R_QAW1 >/dev/null 2>&1
EXIT_CODE=$?
pass_fail "$(gst "SELECT status FROM dw.etl_task_queue WHERE run_id='R_QAW1' AND seq_no=1;")" \
          "SUCCEEDED" "W-1a(前置成功)"
pass_fail "$(gst "SELECT status FROM dw.etl_task_queue WHERE run_id='R_QAW1' AND seq_no=2;")" \
          "FAILED" "W-1b(失败步终态)"
pass_fail "$(gst "SELECT status FROM dw.etl_task_queue WHERE run_id='R_QAW1' AND seq_no=3;")" \
          "SKIPPED" "W-1c(下游被跳过)"
if [ "$EXIT_CODE" != "0" ]; then echo "  W-1d(退出码非0) PASS"; else echo "  W-1d FAIL (exit=0)"; fi

echo "===== W-2  K6 重试：前 2 次失败、第 3 次成功 ====="
# 用**序列**而非计数表实现"第 N 次调用才成功"，两个原因都是必须的：
#   1) nextval 非事务性：任务失败时整个 DELETE+SELECT 事务回滚，若用表计数则
#      计数一起被回滚 -> 永远停在 0 -> 永远失败（实测踩过）。
#   2) 除数必须非常量：`CASE WHEN cond THEN 1 ELSE 1/0 END` 的两个分支都是常量，
#      会被常量折叠，1/0 在计划期即报错，与条件无关（实测踩过）。
#      故写成 1 / greatest(nextval(...) - 2, 0)：第 1、2 次除数为 0 报错，第 3 次为 1。
gst "DROP SEQUENCE IF EXISTS dw.qa_retry_seq;
     CREATE SEQUENCE dw.qa_retry_seq;
     DELETE FROM dw.etl_task_queue WHERE run_id='R_QAW2';
     INSERT INTO dw.etl_task_queue(run_id,step_name,seq_no,depends_on,sql_text,max_attempt)
     VALUES ('R_QAW2','flaky',1,NULL,
       'SELECT 1 / greatest(nextval(''dw.qa_retry_seq'')::int - 2, 0);',
       3);" >/dev/null
bash "$WORKER" --run-id R_QAW2 >/dev/null 2>&1
pass_fail "$(gst "SELECT status FROM dw.etl_task_queue WHERE run_id='R_QAW2';")" \
          "SUCCEEDED" "W-2a(最终成功)"
pass_fail "$(gst "SELECT attempt FROM dw.etl_task_queue WHERE run_id='R_QAW2';")" \
          "3" "W-2b(attempt=3)"

echo "===== W-3  K6 边界：超过 max_attempt 后停止重试 ====="
gst "DELETE FROM dw.etl_task_queue WHERE run_id='R_QAW3';
     INSERT INTO dw.etl_task_queue(run_id,step_name,seq_no,depends_on,sql_text,max_attempt)
     VALUES ('R_QAW3','always_fail',1,NULL,'SELECT 1/0;',2);" >/dev/null
bash "$WORKER" --run-id R_QAW3 >/dev/null 2>&1
pass_fail "$(gst "SELECT status FROM dw.etl_task_queue WHERE run_id='R_QAW3';")" \
          "FAILED" "W-3a(终态 FAILED)"
pass_fail "$(gst "SELECT attempt FROM dw.etl_task_queue WHERE run_id='R_QAW3';")" \
          "2" "W-3b(attempt 停在 max_attempt)"

echo "===== W-4  K8 僵死任务回收 ====="
gst "DELETE FROM dw.etl_task_queue WHERE run_id='R_QAW4';
     INSERT INTO dw.etl_task_queue(run_id,step_name,seq_no,depends_on,sql_text,status,
                                   claimed_by,claimed_at,max_attempt)
     VALUES ('R_QAW4','orphan',1,NULL,'SELECT 1;','CLAIMED','dead-worker',
             now() - interval '3 hours',1);" >/dev/null
bash "$WORKER" --run-id R_QAW4 >/dev/null 2>&1
pass_fail "$(gst "SELECT status FROM dw.etl_task_queue WHERE run_id='R_QAW4';")" \
          "SUCCEEDED" "W-4(僵死任务被回收并完成)"

echo "===== 清理 ====="
gst "DELETE FROM dw.etl_task_queue WHERE run_id LIKE 'R_QAW%';
     DELETE FROM dw.etl_run_log    WHERE run_id LIKE 'R_QAW%';
     DROP SEQUENCE IF EXISTS dw.qa_retry_seq;" >/dev/null
pass_fail "$(gst "SELECT count(*) FROM dw.etl_task_queue WHERE run_id LIKE 'R_QAW%';")" \
          "0" "cleanup"
