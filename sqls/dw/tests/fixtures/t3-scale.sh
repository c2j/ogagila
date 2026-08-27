#!/usr/bin/env bash
# Phase 4 / T3 规模造数驱动
# 存在理由：gsql 不支持 \if，无法在 SQL 内实现参数默认值，故由本驱动提供。
#
# 用法：bash t3-scale.sh [--rentals N] [--payments N] [--months N]
# 默认：20 万 rental / 100 万 payment / 12 个月跨度
set -uo pipefail

CONTAINER=${CONTAINER:-pagila}
N_RENTAL=200000
N_PAYMENT=1000000
MONTHS=12
HERE="$(cd "$(dirname "$0")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --rentals)  N_RENTAL="$2";  shift 2 ;;
    --payments) N_PAYMENT="$2"; shift 2 ;;
    --months)   MONTHS="$2";    shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

echo "[t3] rentals=$N_RENTAL payments=$N_PAYMENT months=$MONTHS"
docker cp "$HERE/t3-scale.sql" "$CONTAINER":/tmp/t3-scale.sql >/dev/null 2>&1
docker exec "$CONTAINER" gsql-pagila \
  -v n_rental="$N_RENTAL" -v n_payment="$N_PAYMENT" -v months="$MONTHS" \
  -f /tmp/t3-scale.sql
