#!/usr/bin/env bash
# Phase 4 / 企业版验证套件驱动 — Q1 剩余项（V1 / SMP 加速比 / Codegen）
#
# 运行前提：企业版或极简版 openGauss（G37：Apple Silicon Docker 不可用，
# 需 x86_64 Linux 或鲲鹏等完整 ARM 服务器）。lite 上运行会输出明确 SKIP。
#
# V1 裁定依据是**计时比**而非计划捕获，三个原因（均实测）：
#   1) openGauss 不支持 `EXPLAIN ... CALL`（语法错误），过程内计划无法用 EXPLAIN 捕获；
#   2) openGauss 不支持 EXPLAIN 作子查询/CTAS（G38），只能独立执行；
#   3) 计时在亚 20ms 区间被噪声主导（lite 上 101 万行聚合 0.158ms~11.5ms 抖动），
#      必须强制 base 中位 > 100ms 才采信加速比，否则报告 INCONCLUSIVE（防假阳性）。
#
# 用法：CONTAINER=<企业版容器> bash qa-enterprise.sh
set -uo pipefail

CONTAINER=${CONTAINER:-pagila}
MIN_BASE_MS=${MIN_BASE_MS:-100}   # 计时可信下限，可调低以在小数据上验证判定分支
HERE="$(cd "$(dirname "$0")" && pwd)"

# 运行 SQL 套件，捕获 \timing 输出
# 前置检查：探针需要足够大的数据才有意义（<100ms 计时被噪声主导）。
# 缺少 T3 规模数据时如实报告并给出加载指引，而非跑出假结论。
ROWS=$(docker exec "$CONTAINER" gsql-pagila -t -A -c   "SELECT count(*) FROM dw.dwd_fact_payment;" 2>/dev/null | tr -d '\r')
echo "  dwd_fact_payment 行数 = ${ROWS:-0}"
if [ "${ROWS:-0}" -lt 1000000 ]; then
  echo ""
  echo "!! 数据规模不足：探针需 >= 100 万行（计时下限 100ms 才可信）"
  echo "!! 请先加载 T3 规模数据："
  echo "!!   bash sqls/dw/tests/fixtures/t3-scale.sh --rentals 200000 --payments 2000000 --months 12"
  echo "!!   并重建 DWD：CALL dw.pkg_dwd.build_dwd_fact_payment(date '2022-01-01', date '2027-01-01', 'R_ENT', a, b);"
  echo "!! 当前结论：INCONCLUSIVE（不判定）"
  exit 0
fi

docker cp "$HERE/qa-enterprise.sql" "$CONTAINER":/tmp/ >/dev/null 2>&1
FULL=$(docker exec "$CONTAINER" gsql-pagila -f /tmp/qa-enterprise.sql 2>&1)

echo "$FULL" | grep -E 'E-0|V15-[0-9]|探针过程|CODEGEN' | head -8

# 解析 Time: xxx ms 序列。顺序固定：dop=1 三次 / dop=4 三次 / 过程内三次
median() { printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
TIMES=($(echo "$FULL" | grep -oE 'Time: [0-9.]+ ms' | grep -oE '[0-9.]+'))
T1=( "${TIMES[@]:0:5}" )     # 顶层 dop=1
T4=( "${TIMES[@]:5:5}" )     # 顶层 dop=4
TP=( "${TIMES[@]:10:5}" )    # 过程内 dop=4
M1=$(median "${T1[@]}"); M4=$(median "${T4[@]}"); MP=$(median "${TP[@]}")

echo ""
echo "===== 计时（中位数 ms，5 次）====="
printf "  顶层 dop=1 : %s  顶层 dop=4 : %s  过程内 dop=4 : %s\n" "$M1" "$M4" "$MP"
if [ "${M1:-0}" = "0" ]; then echo "  未捕获到计时数据，检查 \timing 输出"; exit 1; fi

# 绝对时间下限：base 中位 < 100ms 时计时被噪声主导（实测 0.158ms~11.5ms 抖动），
# 任何加速比都不可信 -> 如实报告 INCONCLUSIVE，避免假阳性裁定。
echo ""
if awk -v m="$M1" -v f="$MIN_BASE_MS" 'BEGIN {exit !(m < f)}'; then
  echo "===== SMP 判定 ====="
  echo "  base 中位 ${M1}ms < ${MIN_BASE_MS}ms 下限 -> 计时不足以判定（INCONCLUSIVE）"
  echo "  >> 需扩大数据规模（如 T3 造数 1000 万+ 行）后重跑本套件"
  SMP_OK=0; PROC_CONCL="INCONCLUSIVE"
else
  SPEEDUP=$(awk -v a="$M1" -v b="$M4" 'BEGIN {printf "%.2f", a/b}')
  echo "===== SMP 判定 ====="
  if awk -v s="$SPEEDUP" 'BEGIN {exit !(s > 1.15)}'; then
    echo "  顶层 dop=4/dop=1 加速比 = ${SPEEDUP}x (>1.15) -> SMP 生效"
    SMP_OK=1
  else
    echo "  顶层 dop=4/dop=1 加速比 = ${SPEEDUP}x (<=1.15) -> SMP 未生效"
    SMP_OK=0
  fi

  echo ""
  echo "===== V1 裁定（G13 是否覆盖 EXECUTE IMMEDIATE）====="
  PROC_SPEEDUP=$(awk -v a="$M1" -v b="$MP" 'BEGIN {printf "%.2f", a/b}')
  echo "  过程内 dop=4 / 顶层 dop=1 = ${PROC_SPEEDUP}x"
  if [ "$SMP_OK" = "1" ] && awk -v s="$PROC_SPEEDUP" 'BEGIN {exit !(s < 1.15)}'; then
    echo "  >> 过程内 EXECUTE IMMEDIATE 无提速 -> G13 同样生效 -> 维持 O1（队列模式）"
  elif [ "$SMP_OK" = "1" ]; then
    echo "  >> 过程内 EXECUTE IMMEDIATE 也有提速 -> G13 不覆盖 -> 可简化为 O3（纯库内）"
  else
    echo "  >> 本实例无 SMP，V1 不可判定 —— 需换企业版/极简版环境"
  fi
fi

echo ""
echo "===== 计划佐证（顶层同一 SQL 的 EXPLAIN，仅作参考）====="
docker exec "$CONTAINER" gsql-pagila -c \
  "SET query_dop=4; EXPLAIN (COSTS OFF) SELECT count(*), sum(amount) FROM dw.dwd_fact_payment; RESET query_dop;" 2>&1 \
  | grep -iE 'Streaming|Gather|dop|Aggregate|Scan' | head -5 || echo "  (无输出)"
