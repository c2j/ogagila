#!/usr/bin/env bash
# Phase 2 QA / Q2.7 — C1 大屏刷新期间并发读不中断
# 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §5.4 / §9 Phase 2（Q2.7）
#
# 用法：bash qa-phase2-c1-concurrent.sh [REPLACE|SWAP]   默认 REPLACE
#
# 断言矩阵：
#   两种模式   ：读会话无 "does not exist" / "could not obtain lock" / deadlock
#   SWAP 额外  ：读到的行数序列不含 0（切换必须原子，读者始终可见旧数据）
set -uo pipefail

CONTAINER=${CONTAINER:-pagila}
MODE=${1:-REPLACE}
TARGET_DATE=${TARGET_DATE:-2025-03-01}
ROUNDS=${ROUNDS:-15}
READ_LOG=/tmp/c1_reads.log
ERR_LOG=/tmp/c1_reads.err

gs() { docker exec "$CONTAINER" gsql-pagila "$@"; }

: > "$READ_LOG"; : > "$ERR_LOG"

# 读会话：持续查询大屏表，记录行数与错误。
(
  for _ in $(seq 1 200); do
    gs -t -A -c "SELECT count(*) FROM dw.ads_screen_store_today WHERE stat_date='${TARGET_DATE}';" \
       >> "$READ_LOG" 2>> "$ERR_LOG"
  done
) &
READER=$!

cat > /tmp/c1_refresh.sql <<EOF
\set ON_ERROR_STOP 0
DECLARE v_rows integer; v_ms numeric;
BEGIN
  FOR i IN 1..${ROUNDS} LOOP
    dw.pkg_ads.build_screen_today(date '${TARGET_DATE}', 'R_Q27', '${MODE}', v_rows, v_ms);
  END LOOP;
END;
/
EOF
docker cp /tmp/c1_refresh.sql "$CONTAINER":/tmp/ >/dev/null 2>&1
gs -f /tmp/c1_refresh.sql >/dev/null 2>&1

kill "$READER" 2>/dev/null; wait "$READER" 2>/dev/null

READS=$(grep -c '^[0-9]' "$READ_LOG" || true)
FATAL=$(grep -icE 'does not exist|could not obtain lock|deadlock' "$ERR_LOG" || true)
ZEROS=$(grep -c '^0$' "$READ_LOG" || true)

echo "===== Q2.7 (mode=$MODE) ====="
echo "  读取次数=$READS  致命错误=$FATAL  读到 0 行次数=$ZEROS"

if [ "$READS" -eq 0 ]; then
  echo "  Q2.7 FAIL (读会话未产生任何结果)"; exit 1
fi
if [ "$FATAL" -ne 0 ]; then
  echo "  Q2.7 FAIL (出现致命错误)"; head -3 "$ERR_LOG"; exit 1
fi
if [ "$MODE" = "SWAP" ] && [ "$ZEROS" -ne 0 ]; then
  echo "  Q2.7 FAIL (SWAP 模式读者看到了 0 行，切换非原子)"; exit 1
fi
echo "  Q2.7 PASS"
