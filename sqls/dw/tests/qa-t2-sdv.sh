#!/usr/bin/env bash
# Phase 3 / T2 驱动 — SDV 分布真实性造数与验证
#
# 完整链路：导出种子 -> SDV 建模采样 -> CSV -> COPY 入 staging -> 断言
#
# 用法：bash qa-t2-sdv.sh [--rows N] [--venv /path/to/venv]
# 前置：venv 中已 pip install sdv（BUSL-1.1 许可证，内部测试用途在授权范围内）
set -uo pipefail

CONTAINER=${CONTAINER:-pagila}
ROWS=20000
VENV=${VENV:-/tmp/sdvenv}
WORK=${WORK:-/tmp/sdv_work}
HERE="$(cd "$(dirname "$0")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --rows) ROWS="$2"; shift 2 ;;
    --venv) VENV="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ ! -x "$VENV/bin/python" ]; then
  echo "FAIL: 未找到 venv ($VENV)。请先 python3 -m venv $VENV && $VENV/bin/pip install sdv" >&2
  exit 1
fi

gs() { docker exec "$CONTAINER" gsql-pagila "$@"; }
mkdir -p "$WORK"

echo "########## 1. 导出种子数据（仅基础 Pagila，排除 T1/T3 造数）##########"
gs -c "\copy (SELECT payment_id, customer_id, staff_id, amount, payment_date
                FROM payment WHERE payment_id < 900000000 ORDER BY payment_id)
       TO '/tmp/seed_payment.csv' WITH CSV HEADER" >/dev/null 2>&1
gs -c "\copy (SELECT rental_id, rental_date, return_date, inventory_id, customer_id, staff_id
                FROM rental WHERE rental_id < 900000000 ORDER BY rental_id)
       TO '/tmp/seed_rental.csv' WITH CSV HEADER" >/dev/null 2>&1
docker cp "$CONTAINER":/tmp/seed_payment.csv "$WORK"/ >/dev/null 2>&1
docker cp "$CONTAINER":/tmp/seed_rental.csv  "$WORK"/ >/dev/null 2>&1
echo "  payment 种子 $(($(wc -l < "$WORK/seed_payment.csv") - 1)) 行 / rental 种子 $(($(wc -l < "$WORK/seed_rental.csv") - 1)) 行"

echo "########## 2. SDV 建模与采样（GaussianCopula + Inequality）##########"
cp "$HERE/../scripts/sdv_gen.py" "$WORK"/
( cd "$WORK" && "$VENV/bin/python" sdv_gen.py --rows "$ROWS" 2>&1 \
    | grep -vE '^\s*$|Warning|warnings.warn|table_data\[' )
SDV_RC=${PIPESTATUS[0]}
if [ "$SDV_RC" != "0" ]; then echo "FAIL: sdv_gen.py 退出码 $SDV_RC" >&2; exit 1; fi

echo "########## 3. CSV -> COPY 入 staging ##########"
gs -c "
DROP TABLE IF EXISTS dw.stg_sdv_payment;
CREATE TABLE dw.stg_sdv_payment (amount numeric(18,2), payment_date timestamptz)
  WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);
DROP TABLE IF EXISTS dw.stg_sdv_rental;
CREATE TABLE dw.stg_sdv_rental (rental_date timestamptz, return_date timestamptz)
  WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);" >/dev/null 2>&1
docker cp "$WORK/synth_payment.csv" "$CONTAINER":/tmp/ >/dev/null 2>&1
docker cp "$WORK/synth_rental.csv"  "$CONTAINER":/tmp/ >/dev/null 2>&1
gs -c "\copy dw.stg_sdv_payment FROM '/tmp/synth_payment.csv' WITH CSV HEADER" 2>&1 | tail -1
gs -c "\copy dw.stg_sdv_rental  FROM '/tmp/synth_rental.csv'  WITH CSV HEADER" 2>&1 | tail -1

echo "########## 4. 断言 ##########"
docker cp "$HERE/qa-t2-sdv.sql" "$CONTAINER":/tmp/ >/dev/null 2>&1
gs -v expected_rows="$ROWS" -f /tmp/qa-t2-sdv.sql 2>&1 | grep -vE '^\s*$|^-+\+|^\(. row'

echo "########## 5. 清理 staging ##########"
gs -c "DROP TABLE IF EXISTS dw.stg_sdv_payment; DROP TABLE IF EXISTS dw.stg_sdv_rental;" >/dev/null 2>&1
echo "  已清理"
