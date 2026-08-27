#!/usr/bin/env bash
# Phase 3 QA 驱动 — C4 披露层
# 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §9 Phase 3
#
# 为什么需要 shell 驱动而不是单个 SQL 脚本：
# 本用例必须演示"存在 CRITICAL -> 拒绝冻结 -> 整改 -> 冻结成功"全流程，
# 整改会删除夹具注入的缺陷行。纯 SQL 脚本无法自行恢复这些行，导致第二次运行
# 时已无 CRITICAL、"应被拒绝"的断言失败（实测踩过）。故由本驱动在每次运行前
# 重载夹具并重建各层，保证受控基线。
#
# 用法：bash qa-phase3-disclose.sh
# 判定：所有 Q3.* 行必须为 PASS。
set -uo pipefail

CONTAINER=${CONTAINER:-pagila}
HERE="$(cd "$(dirname "$0")" && pwd)"

gs() { docker exec "$CONTAINER" gsql-pagila "$@"; }

echo "########## 步骤 1：重载夹具（恢复 CV2/CV12 等注入缺陷）##########"
docker cp "$HERE/fixtures/t1-deterministic.sql" "$CONTAINER":/tmp/t1.sql >/dev/null 2>&1
gs -f /tmp/t1.sql 2>&1 | grep -E 'fixture loaded' -A2 | tail -2

echo "########## 步骤 2：重建 DIM/DWD/DWS ##########"
cat > /tmp/p3_rebuild.sql <<'EOF'
\set ON_ERROR_STOP on
DECLARE v_rows integer; v_status varchar2(16);
BEGIN
  dw.pkg_etl_core.ensure_partitions('payment', 3);
  dw.pkg_etl_core.ensure_partitions('dwd_fact_payment', 3, 'dw');
  dw.pkg_etl_core.ensure_partitions('dwd_fact_rental', 3, 'dw');
  dw.pkg_etl_core.ensure_partitions('dws_sales_day_store_category', 3, 'dw');
  dw.pkg_etl_core.ensure_partitions('dws_sales_day_store_staff', 3, 'dw');
  dw.pkg_etl_core.ensure_partitions('dws_rental_day_store', 3, 'dw');
  dw.pkg_dim.build_all(date '2025-03-01', date '2025-04-01', 'R_P3SETUP');
  dw.pkg_dwd.build_dwd_fact_payment(date '2022-01-01', date '2027-01-01', 'R_P3SETUP', v_rows, v_status);
  dw.pkg_dwd.build_dwd_fact_rental (date '2022-01-01', date '2027-01-01', 'R_P3SETUP', v_rows, v_status);
  dw.pkg_dws.build_all(date '2022-01-01', date '2027-01-01', 'R_P3SETUP');
END;
/
EOF
docker cp /tmp/p3_rebuild.sql "$CONTAINER":/tmp/ >/dev/null 2>&1
gs -f /tmp/p3_rebuild.sql 2>&1 | grep -E 'ERROR' || echo "  rebuild OK"

echo "########## 步骤 3：执行披露层断言 ##########"
docker cp "$HERE/qa-phase3-disclose.sql" "$CONTAINER":/tmp/ >/dev/null 2>&1
gs -f /tmp/qa-phase3-disclose.sql 2>&1 \
  | grep -E 'Q3\.[0-9]+[a-c]? (PASS|FAIL)|restore PASS|^=====' | grep -v CONTEXT

echo "########## 步骤 4：恢复夹具态 ##########"
gs -f /tmp/t1.sql 2>&1 | grep -E 'fixture loaded' -A2 | tail -2
gs -f /tmp/p3_rebuild.sql >/dev/null 2>&1
gs -c "DELETE FROM dw.etl_run_log WHERE run_id LIKE 'R_P3%' OR run_id LIKE 'R_Q3%';" >/dev/null 2>&1
echo "  已还原"
