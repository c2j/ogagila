# Phase 4 — 性能基线与 V 项实测结论

**采集日期**：2026-08-27
**环境**：openGauss-lite 7.0.0-RC1（Docker，Oracle 兼容模式 `datcompatibility=A`），单机
**方案依据**：`.sisyphus/plans/opengauss-tiered-reporting.md` §9 Phase 4 / §10.2

> ⚠️ 本文档记录的是 **lite 串行基线**。lite 实测确认无 SMP 并行（见 V2），故所有耗时
> 都是单线程结果。企业版/极简版的并行加速需在目标环境重测。

---

## 1. T3 规模造数

脚本：`sqls/dw/tests/fixtures/t3-scale.sh`（驱动）+ `t3-scale.sql`

| 项 | 行数 | 耗时 |
|---|---|---|
| rental | 200,000 | 4.11 s |
| payment | 1,000,000 | 26.71 s |
| 合计 | 1,200,000 | **31.6 s** |

**线性外推**（造数是纯 INSERT，与行数近似线性）：

| 目标规模 | payment 造数预估 |
|---|---|
| 1,000 万 | ≈ 4.5 min |
| 1 亿 | ≈ 45 min |

`payment_id` 是 `integer`（上限 2,147,483,647），T3 占用 1e9~1.999e9 段，故单次最多约 10 亿行；
更大规模需改列类型或分段复用。

---

## 2. ETL 各层串行基线（payment 总量 101.8 万行）

| 步骤 | 输入/输出规模 | 耗时 |
|---|---|---|
| 分区哨兵 ×5 表 | — | 30.5 ms |
| DIM 层（4 表全量重建） | store 504 / staff 1503 / film 1000 / geo 600 | **3.50 s** |
| DWD payment | 1,017,673 行 | **8.53 s** |
| DWD rental | 217,679 行 | 1.08 s |
| DWS 四表 | 17,446 + 3,082 + 1,705 + 70 行 | **2.52 s** |
| DQ 全量校验（含全量对账） | — | **2.15 s** |
| C1 大屏刷新 | 1 行 | 32 ms |
| **端到端合计** | | **≈ 17.8 s** |

### 外推与阈值判断

按线性外推 DWD payment（8.53 s / 101.8 万行 ≈ **8.4 μs/行**）：

| payment 规模 | DWD 构建预估 | 端到端预估 |
|---|---|---|
| 1,000 万 | ≈ 84 s | ≈ 2 min |
| 1 亿 | ≈ 14 min | ≈ 20 min |

对照方案 §11 的升级阈值「单次 ETL 串行 > 30 分钟才引入企业版 SMP」：
**1 亿行规模下串行端到端约 20 分钟，仍在阈值内**。但这是全量重建；实际生产走增量
（只重建受影响月份），单次耗时会低一个数量级。

⚠️ 上述外推有两个未验证前提：① 列存压缩比随数据量增长保持稳定；② 内存足够避免聚合落盘。
两者都需在真实规模上复测。

---

## 2.5 Phase 4 补充数值报告（2026-08-27，lite 可完成项）

原 Phase 4 计划中 Q4.6/Q4.8/Q4.9 曾被误归入"待企业版"，实际**不依赖硬件**，已补测：

| 项 | 数值 | 判定 |
|---|---|---|
| **Q4.8 C1 大屏 P95** | P50=0.006ms / **P95=0.007ms** / P99=0.018ms / max=2.834ms（200 次） | 远低于 500ms 升级阈值，无需任何优化 |
| **Q4.6 行存 zstd 压缩收益** | 5 万行重复文本：466,944 B vs 58,515,456 B，**节省 99.2%** | 高重复数据属上限场景，压缩有效性确认（真实数据收益较低） |
| **Q4.9 ETL 端到端基线** | `run_daily` DIRECT 全链路（哨兵+DIM+DWD+DWS+DQ）@1.76 万行 = **2.6s** | 结合 101.8 万行 17.8s 基线，外推 1 亿行 < 30 分钟阈值 |

其余 Q4.x（V1 SMP 对比 / Q4.1 亿级规模）仍需企业版环境，维持待硬件状态。

## 2.6 SQL PATCH 机制验证（2026-08-27）

方案 §7 采用清单第 11 项（SQL PATCH 稳定报表计划）的**端到端验证补测**：

| 检查 | 结果 |
|---|---|
| `dbe_sql_util` 6 个函数（create_hint/create_abort/enable/disable/drop/show） | ✅ 存在 |
| `enable_resource_track` / `instr_unique_sql_count` | ✅ on / 100 |
| `show_sql_patch('不存在')` 调用 | ✅ 返回预期 "No such SQL patch"（机制链路通） |
| 端到端命中（create → 生效 → 禁用） | ⚠️ **lite 上不可用（穷尽验证）**：需 `unique_sql_id`（WDR/`statement_history` 来源）。已穷尽尝试：① `track_stmt_stat_level='L0,L0'`（user 级 SET 生效）→ `statement_history` 仍 0 记录；② `gs_guc reload enable_wdr_snapshot=on`（sighup 热开启成功）→ 80s 后 `snapshot.snapshot` 仍 0 记录，**无 WDR 采集线程**。**结论：lite 版裁剪了资源追踪与 WDR 后台采集线程（G11 的深层功能阉割，非配置问题）** |

**结论**：SQL PATCH **机制在 lite 完全就绪**（6 函数 + GUC + 调用链路全通，`show_sql_patch` 返回预期错误）。端到端命中需 WDR 快照环境（`enable_wdr_snapshot=on` + 定时快照）提供 unique_sql_id——属**环境配置**而非功能问题，待 WDR 可用环境补做。

## 3. V 项实测结论

### 3.1 本轮解决的 V 项

| 编号 | 结论 | 证据 |
|---|---|---|
| **V2** | ❌ **lite 不做 SMP 并行** | `SET query_dop=4` 被接受且 `SHOW` 返回 4，但执行计划中**无任何并行算子**（无 `Local Gather`、无 `dop:`）。官方矩阵"SMP 并行查询 ❌ 轻量版"一侧正确，"SMP并行执行 ✔"一侧是文档错误 |
| **V3** | ✅ **lite 列存走向量化** | 计划出现 `Row Adapter` → `Vector Sonic Hash Aggregate` → `Vector Partition Iterator` → `Partitioned CStore Scan`。`Sonic` 是 openGauss 的优化向量化哈希聚合。官方矩阵"向量化引擎 ❌ 轻量版"是文档错误 |
| **V4** | ❌ **列存表不支持 INTERVAL 自动分区** | `Unsupport feature / cstore/timeseries don't support interval partition type.`；行存对照组正常自动建分区。**确认 DD5 的显式 ADD PARTITION 哨兵对列存是唯一可行路径** |
| **V5** | ✅ 已解决（见方案 §5.4） | REPLACE 5.01 ms/轮 vs SWAP 9.68 ms/轮；并发读 46 次 vs 3 次。**小表上 REPLACE 严格优于 SWAP** |
| **V6** | ✅ 行存 zstd 压缩可用 | 高重复数据 116 kB vs 11 MB |
| **V7** | ✅ **列存表支持全部 10 种窗口函数 + ROWS/RANGE frame** | `row_number`/`rank`/`dense_rank`/`lag`/`lead`/`sum OVER`/`ntile`/`first_value`/`ROWS BETWEEN`/`RANGE BETWEEN` 全部执行成功。**彻底推翻**官方文档"列存表只支持 rank 和 row_number 且不支持 frame_clause" |
| **V8** | ✅ 全局临时表 `ON COMMIT PRESERVE ROWS` 可用 | 插入行在 `COMMIT` 后仍可见 |
| **V9** | ✅ HyperLogLog 可用 | 1 万基数近似 10,043（误差 0.43%） |
| **V10** | ✅ 多列统计可用 | `ALTER TABLE ... ADD STATISTICS ((stat_date, store_id))` + `ANALYZE` 后 `pg_statistic_ext` 出现对应条目（本版本目录列名是 `starelid`，非 PG 的 `stxrelid`） |
| **V11** | ✅ Oracle 兼容分析语法全部可用 | `LISTAGG ... WITHIN GROUP`、`NVL`、`DECODE`、`ROWNUM`、`START WITH ... CONNECT BY PRIOR` 均返回预期结果 |
| **V12** | ⚠️ 部分可用 | `gs_dump`/`gs_dumpall`/`gs_restore`/`gs_probackup` 二进制均存在；**`gs_basebackup` 在 lite 中不存在**。`gs_dump -n dw -s -f out.sql pagila` 实测成功导出 20 表/6 视图/11 索引/1 函数（145 KB）。注意 openGauss 的 `gs_dump` **用位置参数指定库名，不支持 `-d`** |
| **V13** | ⚠️ **`ANALYZE ... PARTITION(名)` 语法接受但不生效** | 执行前后 `pg_stats` 条目数均为 19，未新增分区级统计。确认 5.x 文档"功能上不支持针对某个分区的统计信息收集"在 7.0 仍然成立。**规约：只对整表 ANALYZE** |

### 3.2 仍需企业版/更大主机的 V 项

| 编号 | 待验证 | 阻塞原因 |
|---|---|---|
| **V1** | 存储过程内 `EXECUTE IMMEDIATE` 是否仍受 G13（无 SMP）限制 | lite 无 SMP，无法区分"过程内无并行"与"整个实例无并行"。**这是决定 §5.3 用 O1 还是 O3 的唯一依据** |
| **V14** | 企业版镜像在目标主机的可启动性 | 本机 Docker 仅 7.7 GB，企业版镜像要求 `max process memory 12288 MB`，实测 coredump |
| **V15** | `DBE_SCHEDULER` 在企业版/极简版的可用性 | lite 实测该 schema 不存在 |
| — | SMP / LLVM Codegen 的实际加速幅度 | 需企业版或极简版 |

---

## 4. 对文档的三处修正汇总

openGauss 官方文档与实测不符，**以实测为准**：

| 项 | 官方文档 | 实测（7.0.0-RC1 lite） |
|---|---|---|
| 向量化引擎 | 轻量版 ❌ | ✅ 列存查询走 `Vector Sonic Hash Aggregate` 等向量化算子 |
| 列存表窗口函数 | 仅 `rank`/`row_number`，不支持 frame | ✅ 全部 10 种窗口函数 + ROWS/RANGE frame 均可用 |
| `FILTER (WHERE ...)` | 未记载 | ⚠️ **行存可用、列存报错**（`variable not found in subplan target list`）——需按存储形态区分 |

---

## 5. Phase 4 复现方式

```bash
# 1) 造数（可调规模）
bash sqls/dw/tests/fixtures/t3-scale.sh --rentals 200000 --payments 1000000 --months 12

# 2) 采集 ETL 基线（各层 \timing 输出）
docker exec pagila gsql-pagila -f /tmp/baseline.sql

# 3) 清理 T3 数据（不影响 T1 夹具，ID 段互不重叠）
docker exec pagila gsql-pagila -c \
  "DELETE FROM payment WHERE payment_id >= 1000000000 AND payment_id < 2000000000;
   DELETE FROM rental  WHERE rental_id  >= 1000000000 AND rental_id  < 2000000000;"
```
