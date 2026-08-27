# openGauss 分层报表体系 — 实施方案

**版本**：v1（待评审）
**日期**：2026-08-27
**仓库**：`ogagila`（Pagila 的 openGauss 移植版）
**作者**：Sisyphus

---

## 1. 背景与目标

### 1.1 业务需求（用户原话）

> 业务方面希望能出一些给门店大屏展示、中层领导、高层领导、上市公司报告等不同层次的报表，建议用存储过程实现相关数据处理功能。

四类消费者：

| 编号 | 消费者 | 核心诉求 |
|---|---|---|
| C1 | 门店大屏 | 店内实时/准实时滚动展示 |
| C2 | 中层领导 | 日/周/月运营指标，需多维下钻 |
| C3 | 高层领导 | 趋势、同比环比、TOP N |
| C4 | 上市公司报告 | 对外披露口径，需合规、可审计、可重算、数据冻结 |

### 1.2 用户明确的方向性约束（本方案的输入前提，不可自行更改）

| 编号 | 约束 | 来源 |
|---|---|---|
| R1 | **按生产级高要求设计**。当前库内仅少量造数，**禁止以该数据规模推断设计** | 用户 |
| R2 | 目标规模：**payment 年增 1000 万 ~ 1 亿行** | 用户答复 |
| R3 | 因与 openGauss 有合作关系，**优先采用 openGauss 特有功能** | 用户 |
| R4 | 调度：**触发在外部、编排在库内** | 用户确认 |
| R5 | **先按企业版设计，当前环境用 lite 做功能验证** | 用户答复 |
| R6 | 引入 **SDV（Synthetic Data Vault）** 造数后验证 | 用户 |
| R7 | **先功能、后性能** | 用户 |
| R8 | 用**存储过程**实现数据处理 | 用户 |

### 1.3 本方案目标

1. 交付一套可落地的分层报表数据架构（表/视图/存储过程/调度）。
2. 优先采用 openGauss 特有能力，并明确每项的版本归属（企业版 / 极简版 / 轻量版）。
3. 交付造数与验证方案，**功能正确性优先**，性能压测置后。
4. 显式列出所有**未决问题**与**需实测项**，不做无依据假设。

### 1.4 非目标（本方案不做）

- 不做 BI 前端 / 报表渲染层。
- 不改造 Pagila 源业务表结构（除必要的索引与分区兜底，见 6.1）。
- 不做跨库/跨实例数据同步（源库与数仓同实例，见 4.2）。
- 不做实时流式计算（Flink/Kafka 类）。
- 不做权限/脱敏体系设计（仅预留接口）。

---

## 2. 前提事实基线（已实测确认，方案基于此）

> 以下均为在本机 `pagila` 容器（openGauss-lite 7.0.0-RC1 build 10d38387，Oracle 兼容模式 `datcompatibility=A`）上的实测结果，或 docs.opengauss.org 官方文档结论。**评审时如对某条有疑，可按 §9 的验证脚本复现。**

### 2.1 当前数据现状（仅作"造数起点"，不作设计依据）

| 表 | 行数 | 时间范围 |
|---|---|---|
| payment | 16,049 | 2022-01-23 ~ 2022-07-27 |
| rental | 16,044 | 2022-02-14 ~ 2022-08-23（183 条 `return_date IS NULL`） |
| customer | 599 | `create_date` 全为 2022-02-14 |
| inventory | 4,581 | — |
| film | 1,000 | — |
| store | **500 行** | — |
| staff | **1,500 行** | — |
| category 16 / city 600 / country 109 / actor 200 | — | — |

**已实测的数据质量缺陷（造数与 DQ 规则必须覆盖）**：

| 编号 | 缺陷 | 实测证据 |
|---|---|---|
| D1 | `store` 500 行（store_id 0~499），但**仅 store_id=1、2 有业务数据**（inventory 2270/2311，customer 326/273） | 实测 |
| D2 | `staff` 1500 行分布在 475 个 store_id 上，但 **payment 仅由 2 个 staff 产生** | 实测 |
| D3 | **store_id=2 没有任何 staff 行**（store_id=1 有 6 个） | 实测 |
| D4 | `rental` 最大日期 2022-08-23 **超出** payment 最大日期 2022-07-27 | 实测 |
| D5 | `store.manager_staff_id` 有唯一索引但**无 FK 约束** | schema.sql |
| D6 | 首月（2022-01 从 23 日起）与末月（2022-07 到 27 日止）**不完整** | 实测 |

### 2.2 源表结构关键约束

| 编号 | 事实 |
|---|---|
| S1 | `payment` 是 RANGE 分区表，分区键 `payment_date`，主键 `(payment_date, payment_id)` 复合，7 个月分区（2022-02-01 ~ 2022-08-01 UTC 边界）|
| S2 | `payment` **无 DEFAULT/MAXVALUE 兜底分区** → `payment_date >= 2022-08-01` 插入直接报错（实测 ADD PARTITION 后可插入）|
| S3 | `payment` **是唯一没有 `last_update` 列的表** → 增量水位线只能用 `payment_id` 或 `payment_date` |
| S4 | 其余 14 表有 `last_update timestamptz`，由 `last_updated()` 触发器维护，但触发器是 **BEFORE UPDATE ONLY**（INSERT 走 `DEFAULT now()`）；**DELETE 无任何痕迹** |
| S5 | 金额列：`payment.amount numeric(5,2)`（上限 999.99）、`film.rental_rate numeric(4,2)`、`film.replacement_cost numeric(5,2)` |
| S6 | 缺索引（有 FK 无索引）：`payment.rental_id`、`rental.customer_id`、`rental.staff_id`、`film_category.category_id` |
| S7 | 现有 1 个物化视图 `rental_by_category`（`WITH NO DATA`）+ 7 个普通视图；**不存在任何汇总表** |
| S8 | 分区边界字面量为 **UTC**，汇总区间参数必须与之对齐 |

### 2.3 openGauss 能力实测结论（**含 4 处对官方文档的修正**）

#### 2.3.1 实测修正了文档结论的项

| 项 | 官方文档结论 | **本机实测结果** | 影响 |
|---|---|---|---|
| `FILTER (WHERE ...)` | 文档未记载，librarian 判"很可能不支持" | ✅ **可用**（`count(*) FILTER (WHERE amount>5)` 正常返回） | 条件聚合可直接用 |
| `GROUPING()` | 不确定 | ✅ **可用**（配 ROLLUP 正确返回 0/1） | 下钻小计行可精确标识 |
| 列存表窗口函数 | 官方称仅 `rank`/`row_number`，不支持 frame | ⚠️ **`sum() OVER (PARTITION BY)` 在列存表上实测可用** | 与文档冲突，**列为需复测项 V7** |
| `DBE_SCHEDULER` / `DBE_TASK` | 内核存在，lite 需实测 | ❌ **schema 根本不存在**（lite）| 库内调度只剩 `PKG_SERVICE` |

#### 2.3.2 实测确认的硬约束

| 编号 | 约束 | 实测证据 |
|---|---|---|
| G1 | **增量物化视图（IMMV）不支持 GROUP BY** → `ERROR: Feature not supported / DETAIL: group clause` | 实测 |
| G2 | `REFRESH MATERIALIZED VIEW ... CONCURRENTLY` **语法不支持** | 实测（syntax error） |
| G3 | `months_between` 不存在（需 whale 扩展）；`add_months`/`trunc`/`sysdate`/`last_day` 可用 | 实测 |
| G4 | `sum(numeric(5,2))` **自动提升为无约束 `numeric`**（全量 67416.51 不溢出）→ 溢出风险只在**汇总表目标列 DDL** | 实测 |
| G5 | 存储过程内 `COMMIT` 可用；`PRAGMA AUTONOMOUS_TRANSACTION` 可用（主事务因 `RAISE_APPLICATION_ERROR(-20001)` 回滚后，审计日志仍持久化） | 实测 |
| G6 | `PACKAGE` / `PACKAGE BODY` 可用；`MERGE INTO` 可用且**幂等**（重跑 2 次均 7 行、金额一致） | 实测 |
| G7 | `ALTER TABLE payment ADD PARTITION` / 跨月插入 / `DROP PARTITION` 全部可用 | 实测 |
| G8 | `LAG` 环比可用；`LAG(amt, 12)` 同比基线**全 NULL**（只有 7 个月数据） | 实测 |
| G9 | lite schema 仅有：`dbe_perf`、`dbe_pldebugger`、`dbe_pldeveloper`、`dbe_sql_util`、`pkg_service`。**`dbe_sql_util` 存在 → SQL PATCH 在 lite 可用** | 实测 |
| G10 | `pkg_service` 有 6 个过程：`job_submit`/`job_update`/`job_cancel`/`job_finish`/`submit_on_nodes`/`isubmit_on_nodes`。实测提交 job id=10046 成功并取消 | 实测 |
| G11 | lite GUC 实测：`enable_vector_engine=on`、`try_vector_engine_strategy=off`、`enable_codegen=off`、`query_dop=1`、`enable_delta_store=off`、`enable_ustore=on`、`enable_default_ustore_table=off`、`job_queue_processes=10`、`enable_wdr_snapshot=off`、`enable_asp=on`、`enable_stmt_track=on`、`instr_unique_sql_count=100`、`work_mem=64MB`。⚠️ **参数开启 ≠ 采集可用（G42）**：`enable_asp=on`/`enable_stmt_track=on` 的采集线程在 lite 被阉割，`gs_asp` 与 `statement_history` 实测均 0 记录 | 实测 |
| G12 | 企业版镜像在本机无法启动。初判为内存不足（要求 12GB / 实有 7.7GB）；**后经 G37 实测修正：内存并非根因** | 实测 |
| G37 | 企业版 `libkvecturbo.so` 启动期无条件加载，CPU 特性不匹配即退出（`KVecturbo: ... please check CPU architect`）。镜像入口支持 `OTHER_PG_CONF` 环境变量追加任意 GUC；`GAUSSLOG` 必须显式设置 | 实测 |

#### 2.3.3 官方文档级硬约束（**两条决定架构**）

| 编号 | 约束 | 出处 |
|---|---|---|
| **G13** | **存储过程和函数内的查询不支持并行执行（SMP）——企业版亦然** | [配置并行查询功能](https://docs.opengauss.org/zh/docs/latest/performance_tuning_guide/configuring_the_parallel_query_function.html) |
| **G14** | **IMMV 仅支持"单表查询"与"多单表 UNION ALL"，全版本均不支持 GROUP BY/聚合、不支持列存、不支持分区表** | [incremental_materialized_view](https://docs.opengauss.org/zh/docs/latest/sql_reference/incremental_materialized_view.html)、[7.0.0-RC1 增量物化视图](https://docs.opengauss.org/zh/docs/7.0.0-RC1/docs/SQLReference/增量物化视图.html) |
| G15 | 二级分区表（SUBPARTITION）**仅行存**、**不支持 UPSERT、不支持 MERGE INTO**、每分区键仅 1 列 | [create_table_subpartition](https://docs.opengauss.org/zh/docs/latest/sql_reference/create_table_subpartition.html) |
| G16 | 列存表：**不支持外键**；表级约束仅 `PARTIAL CLUSTER KEY`/`UNIQUE`/`PK`；索引仅 `PSORT`(默认)/`btree`/`gin`(仅 tsvector)；**仅支持 RANGE 分区**；`ORIENTATION` 建后不可改；不支持 `CONCURRENTLY` 建索引；`ON DUPLICATE KEY UPDATE` 不支持列存 | [create_table](https://docs.opengauss.org/zh/docs/latest/sql_reference/create_table.html) |
| G17 | 全局临时表（GTT）**不支持并行扫描、不支持分区、不支持列存**、不响应自动清理 | [global_temporary_table](https://docs.opengauss.org/zh/docs/latest/characteristic_description/global_temporary_table.html) |
| G18 | 分区 ALTER 未声明 `UPDATE GLOBAL INDEX` 时 **GLOBAL 索引失效**；`SELECT ... PARTITION(...)` 指定分区查询**不能走全局索引** | [create_index](https://docs.opengauss.org/zh/docs/latest/sql_reference/create_index.html) |
| G19 | `ANALYZE table PARTITION(名)` **语法支持但功能上不支持按单分区收集统计**（整表分析）；表行数 > 1,600,000 建议 `default_statistics_target=-2`（2% 采样） | [update_statistics](https://docs.opengauss.org/zh/docs/latest/performance_tuning_guide/update_statistics.html) |
| G20 | `job_queue_processes` 是 **postmaster 级参数，需重启生效**（1~1000）；job 连续失败 16 次自动置 `d`（禁用） | [scheduled_task](https://docs.opengauss.org/zh/docs/latest/database_reference/scheduled_task.html) |

#### 2.3.4 版本能力归属（决定 R5 的落地）

| 能力 | 企业版 | 极简版 | 轻量版(lite) |
|---|---|---|---|
| SMP 并行查询 (`query_dop`) | ✔ | ✔ | **❌**（矩阵内部自相矛盾，见 §10-U1） |
| 支持 LLVM / Codegen | ✔ | ✔ | **❌** |
| 向量化引擎 | ✔ | ✔ | **❌**（与"行列混合存储 ✔"矛盾，见 §10-U1） |
| 行列混合存储（列存表） | ✔ | ✔ | **✔** |
| 行存转向量化 (`try_vector_engine_strategy`) | ✔ | ✔ | ❌ |
| HTAP 行列融合 | ✔ | ✔ | ❌ |
| MOT / 全密态 / ORC / Kerberos | ✔ | ✔ | ❌ |
| CM 集群管理 / OM 运维 | ✔ | ❌ | ❌ |
| 主备机 | ✔ | ✔ | ✔（无自动切换） |
| 分区 / 物化视图 / SQL hint / 高级分析函数 | ✔ | ✔ | ✔ |
| 自治事务 / 全局临时表 / ROWNUM / HyperLogLog | ✔ | ✔ | ✔ |
| Ustore (In-place Update) | ✔ | ✔ | ✔ |
| WDR / 慢SQL / Session诊断 / SQL PATCH | ✔ | ✔ | ✔ |
| 行存压缩(OLTP) / 自适应压缩(列存) | ✔ | ✔ | ✔ |
| `DBE_SCHEDULER` / `DBE_TASK` | ✔ | ? | **❌**（实测 schema 不存在） |
| postgres_fdw / dblink / PL/Java(需 JRE) | ✔ | ✔ | ❌ |

> **关键洞察**：**极简版**是被忽略的中间选项 —— 拥有 SMP/LLVM/向量化/HTAP，仅缺 CM/OM。若不需要自动故障切换，极简版即可拿到全部分析型加速能力。**这是需用户决策的未决问题 §10-Q1。**

---

## 3. 关键设计决策与理由

| 编号 | 决策 | 理由 | 被否方案 |
|---|---|---|---|
| **DD1** | 采用 **4 层**：DIM/DWD/DWS/ADS（不设独立 ODS 全量复制层） | R2 规模下 DWD 物理化必要（避免每次聚合重扫 1 亿行原始表 + 大 join）；但源库与数仓同实例，全量 ODS 复制翻倍存储且引入必然腐烂的同步管线。审计需求用"输入指纹 + 期间快照"满足而非全量副本（见 DD8） | 单纯视图分层（1 亿行下重复扫描不可接受）；四层含 ODS 全量复制（存储翻倍、无收益） |
| **DD2** | DWD/DWS 事实表用**列存 `ORIENTATION=COLUMN, COMPRESSION=HIGH`** | 官方明确列存适用"统计分析类查询（关联、分组多）、一次性大批量插入、大宽表"，正是本场景；lite 也支持（矩阵 ✔），实测可建可查 | 全行存（1 亿行聚合扫描代价高、无压缩收益） |
| **DD3** | DWD 事实表**维度退化**（store/staff/category/city/country 冗余进事实表） | 避免 1 亿行事实表与维表的大 join；列存宽表是官方推荐形态；同时规避 G16（列存不支持 FK，本来就无法建 FK 约束） | 严格星型 join（1 亿行 join 代价高） |
| **DD4** | DWD 按 `stat_date` **RANGE 月分区**；DWS 按 `stat_month`/`stat_date` RANGE 分区 | 分区裁剪实测有效（Iterations:1，3.6ms）；G16 列存仅支持 RANGE 分区，与之相容 | 二级分区（G15：仅行存 + 不支持 MERGE/UPSERT，与 DD2/DD6 冲突） |
| **DD5** | 分区维护用**显式 `ADD PARTITION` 哨兵过程**，不用 INTERVAL 自动分区 | INTERVAL 分区**不支持手动 ADD PARTITION**（失去应急能力）；且"列存 + INTERVAL"组合未经验证（列为 §10-V4）。显式哨兵可控、可告警 | INTERVAL 自动分区（失去应急能力 + 组合未验证） |
| **DD6** | 幂等写入统一用 **`DELETE 区间 + INSERT`**，不用 MERGE | 列存表不支持 `ON DUPLICATE KEY UPDATE`（G16）；MERGE **不删除源侧已删除的行**（留幽灵行）；`DELETE+INSERT` 天然处理删除、天然幂等、可 diff。MERGE 仅用于行存小表（如 DWS 月粒度回补） | 纯 MERGE（幽灵行 + 列存不适用）；`ON DUPLICATE KEY UPDATE`（列存不支持） |
| **DD7** | **放弃增量物化视图（IMMV）** | G14：全版本不支持 GROUP BY/聚合、不支持列存、不支持分区表 → 对汇总场景零价值。汇总用物理表 + 存储过程 | IMMV 作为汇总层（技术上不可行） |
| **DD8** | 披露层用**不可变快照表 + 输入指纹 + 口径版本 + 期间锁定**四件套 | S3/S4 决定了源表无法回溯历史状态（payment 无 last_update、DELETE 无痕迹）→ "可重算"必须靠冻结输入指纹与输出快照实现，不能靠重扫源表 | 仅冻结输出（无法证明输入未变） |
| **DD9** | 重型聚合 SQL **不写在存储过程体内**，由库内编排过程通过**外部可控的顶层语句**提交（详见 §5.3 与 §10-Q2） | **G13：存储过程内查询不支持 SMP 并行（企业版亦然）**。1 亿行聚合若锁在过程内，永久放弃多核加速 | 全部逻辑塞进存储过程（放弃 SMP） |
| **DD10** | 调度：**外部 cron/K8s CronJob 触发 → 库内 `PKG_ORCH` 编排** | R4 用户已确认。`DBE_SCHEDULER`/`DBE_TASK` 在 lite 实测不存在（G9）；`job_queue_processes` 需重启生效（G20）且与容器生命周期耦合 | 库内 job 全权调度（lite 无 DBE_SCHEDULER + 重启依赖） |
| **DD11** | 造数用**三层方案**：确定性 SQL 夹具（正确性）+ SDV（分布真实性）+ SQL 批量生成（规模） | SDV 官方明示 HMA "**not meant for scale**"、限"约 5 表 1 层深度"，Pagila 是 15 表多层；且 SDV 值不可预知，无法做断言。R6 要求引入 SDV → 用在它擅长的"分布真实性"环节 | 纯 SDV（15 表/1 亿行不可行 + 无法断言）；纯 SQL（放弃 R6） |
| **DD12** | 采用 Gauss 特有能力清单见 §7，**每项标注版本归属**；lite 不具备的项设计为**可开关增强**，核心功能不依赖 | R3 + R5：先按企业版设计，lite 做功能验证 → 核心逻辑必须在 lite 可跑 | 硬依赖企业版特性（lite 无法功能验证，违背 R5） |

---

## 4. 分层架构

### 4.1 分层总览

```
┌─ L0 源层（既有业务表，不改结构） ─────────────────────────────┐
│  payment(RANGE月分区) rental customer inventory film store ...  │
└───────────────────────┬────────────────────────────────────────┘
                        │ 增量抽取（水位线，见 §6）
┌───────────────────────▼─── L1 DWD 明细层 ─────────────────────┐
│  dwd_fact_payment   列存 + RANGE月分区 + 维度退化（宽表）      │
│  dwd_fact_rental    列存 + RANGE月分区                        │
│  dim_store / dim_staff / dim_film / dim_geo   行存小表         │
│  ↑ 门店有效性口径(store_status) 在 dim_store 落地              │
└───────────────────────┬────────────────────────────────────────┘
┌───────────────────────▼─── L2 DWS 汇总层（SSOT） ─────────────┐
│  dws_sales_day_store_category   列存 + RANGE月分区            │
│  dws_sales_day_store_staff      列存 + RANGE月分区            │
│  dws_sales_month_store          行存（小） + Ustore           │
│  dws_rental_day_store           列存 + RANGE月分区            │
└───────────────────────┬────────────────────────────────────────┘
┌───────────────────────▼─── L3 ADS 应用层（按消费者分化） ─────┐
│  C1 大屏  : ads_screen_store_today  行存小表(准实时) + 视图     │
│  C2 中层  : v_ads_ops_*    视图（GROUPING SETS 下钻）          │
│  C3 高层  : v_ads_exec_*   视图（LAG/RANK 窗口）               │
│  C4 披露  : rpt_disclosure_snapshot  行存不可变快照表           │
└────────────────────────────────────────────────────────────────┘
┌─ 旁路层（贯穿） ───────────────────────────────────────────────┐
│  etl_run_log  etl_watermark  dq_check_result                   │
│  rpt_period_close  rpt_metric_def  rpt_source_fingerprint      │
└────────────────────────────────────────────────────────────────┘
```

### 4.2 各层职责与载体

| 层 | 职责 | 载体 | 存储形态 | 刷新 |
|---|---|---|---|---|
| **DIM** | 维度标准化；**门店有效性口径**（D1/D2/D3 拦截点） | 物理表 `dim_*` | 行存 + `compresstype=2` | 每日全量重建（维表小） |
| **DWD** | 清洗 + 维度退化 + 统一分析截止日 | 物理表 `dwd_fact_*` | **列存 + RANGE 月分区 + COMPRESSION=HIGH** | 每日增量（`DELETE 区间+INSERT`） |
| **DWS** | 唯一物理事实汇总层（SSOT），多粒度 | 物理表 `dws_*` | 列存（日粒度）/ 行存+Ustore（月粒度） | 每日增量 + 每月回补 |
| **ADS** | 面向 4 类消费者的口径出口 | C1 行存小表；C2/C3 视图；C4 不可变快照表 | 见上 | C1 准实时；C2/C3 随 DWS；C4 人工冻结 |

**为什么 DWD 必须物理化**（对应 R1/R2）：1 亿行/年规模下，若 DWD 仅为视图，每次 DWS 构建都要重扫原始 payment 分区 + 与 5 张维表 join。物理化 + 维度退化后，DWS 构建只扫单张列存宽表的目标分区。

**为什么不设独立 ODS 全量复制层**：源库与数仓同实例，全量复制使存储翻倍且引入同步管线。审计所需的"输入可证"由 `rpt_source_fingerprint`（行数/金额和/主键区间/校验和）满足（DD8）。
**风险与缓解**：若未来数仓需与业务库物理隔离（不同实例/只读备库），需补 ODS 层。触发条件写入 §11 升级阈值。

### 4.3 四类报表的差异化实现

| 消费者 | 新鲜度 | 载体 | 关键技术 | 刷新期可用性 |
|---|---|---|---|---|
| **C1 大屏** | 准实时 30s~5min | `ads_screen_store_today` **行存小表**（仅当日 × 有效门店）+ 视图 | 当日增量小表 `UNION ALL` DWS 历史；**HyperLogLog** 做近似 UV | 小表重建耗时短；**G2 决定无法用 MV CONCURRENTLY**，故用小表整体替换（见 §5.4） |
| **C2 中层** | T+1（每日 02:00） | `v_ads_ops_*` 视图 over DWS | `GROUPING SETS`/`ROLLUP` + **`GROUPING()`**（实测可用）一次出多粒度 | 视图无刷新 |
| **C3 高层** | T+1 | `v_ads_exec_*` 视图 over DWS | `LAG`/`RANK`/移动平均；**必须先生成完整月份骨架**（见 §8.3） | 视图无刷新 |
| **C4 披露** | 期末人工触发 | `rpt_disclosure_snapshot` 行存不可变表 | 四件套 + `BEFORE UPDATE/DELETE` 触发器拒绝修改；`gs_probackup` 物理备份留存 | 快照只增版本不覆盖 |

---

## 5. 存储过程组织

### 5.1 PACKAGE 划分

> 实测 `PACKAGE`/`PACKAGE BODY` 在 lite 可用（G6）。**硬约束：包内只允许常量，禁止包级可变状态**（openGauss 包变量是会话级，连接池下会串话）。

| PACKAGE | 职责 |
|---|---|
| `PKG_ETL_CORE` | `run_id` 生成、`etl_run_log` 读写、水位线读写、`ensure_partitions` 分区哨兵、工具函数 |
| `PKG_DIM` | `build_dim_store` / `build_dim_staff` / `build_dim_film` / `build_dim_geo` |
| `PKG_DWD` | `build_dwd_fact_payment` / `build_dwd_fact_rental` |
| `PKG_DWS` | `build_dws_sales_day_*` / `build_dws_sales_month_store` / `build_dws_rental_day_store` |
| `PKG_ADS` | `build_ads_screen_today`（C1 小表重建） |
| `PKG_DQ` | 各 DQ 规则校验，写 `dq_check_result` |
| `PKG_DISCLOSE` | `take_fingerprint` / `close_period` / `recompute_period` |
| `PKG_ORCH` | `run_daily(p_date)` / `run_monthly(p_period)` / `run_screen()` 编排 |

C2/C3 是**视图**，不属于任何 PACKAGE。

### 5.2 统一签名约定（强制）

```sql
PROCEDURE build_xxx(
  p_date_from IN  date,        -- 半开区间起 [ ，永远半开，防分区裁剪失效
  p_date_to   IN  date,        -- 半开区间止 )
  p_run_id    IN  varchar2,
  p_force     IN  boolean DEFAULT false,
  o_rows      OUT integer,
  o_status    OUT varchar2     -- OK | WARN | FAILED
);
```

### 5.3 幂等性与事务边界（**含 G13 的处理**）

**幂等唯一规则**：每个 `build_*` 过程第一条语句必须是
`DELETE FROM 目标 WHERE stat_date >= p_date_from AND stat_date < p_date_to;`
随后 INSERT，**全程单事务**。目标表加 `UNIQUE(stat_date, <维度键>)` 作为**防御性护栏**，不作为写入机制。

**事务边界**：
- **禁止在 `build_*` 过程内 `COMMIT`**（虽实测可用 G5）—— 一旦 COMMIT，失败留半成品，幂等性与"上一版可用"同时崩掉。
- **`PRAGMA AUTONOMOUS_TRANSACTION` 仅用于两处**：`etl_run_log` 失败记录、`dq_check_result` 写入。实测验证：主事务因 `RAISE_APPLICATION_ERROR(-20001)` 回滚后，自治事务写入的审计日志仍持久化（G5）。

**G13（存储过程内无 SMP）的处理 —— 三选项，需用户决策（§10-Q2）**：

| 选项 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **O1（默认推荐）** | 库内编排过程只做控制流；重型 `INSERT...SELECT` 由 `PKG_ORCH` 生成 SQL 文本写入 `etl_task_queue`，外部 worker 逐条以**顶层语句**提交 | 保留 SMP；仍满足 R4"编排在库内"（编排逻辑与顺序在库内定义） | 外部 worker 需要一个执行循环；SQL 文本跨边界 |
| **O2** | 全部逻辑在存储过程内，接受串行 | 最简单，纯库内 | 1 亿行聚合放弃多核；**违背 R1 高要求** |
| **O3** | 存储过程内用 `EXECUTE IMMEDIATE` 执行重型 SQL | 纯库内 | **是否仍受 G13 限制未经验证**（列为 §10-V1） |

> 本方案按 **O1** 设计，但 O3 若实测可行则退化为更简单的纯库内方案。**这是最需要评审关注的架构张力。**

#### 5.3.1 `etl_task_queue` 表结构（O1 的接口契约）

> 所有数仓对象位于独立 schema **`dw`**（避免污染 `public` 的 Pagila 源对象）。注意连接用户 `gaussdb` 的 `search_path` 为 `"$user", public`，故**必须全限定命名**。

```sql
CREATE TABLE dw.etl_task_queue (
  task_id        bigint       NOT NULL DEFAULT nextval('dw.etl_task_queue_seq'),
  run_id         varchar(64)  NOT NULL,           -- 归属批次
  step_name      varchar(128) NOT NULL,           -- 如 'dws_sales_day_store_category'
  seq_no         integer      NOT NULL,           -- 同 run_id 内执行顺序，小者先
  depends_on     integer,                         -- 依赖的 seq_no；NULL=无依赖
  sql_text       text         NOT NULL,           -- 待执行的顶层 SQL
  status         varchar(16)  NOT NULL DEFAULT 'PENDING',
                 -- PENDING -> CLAIMED -> RUNNING -> SUCCEEDED | FAILED | SKIPPED
  claimed_by     varchar(64),                     -- worker 标识（hostname:pid）
  claimed_at     timestamptz,
  started_at     timestamptz,
  finished_at    timestamptz,
  affected_rows  bigint,
  attempt        integer      NOT NULL DEFAULT 0,
  max_attempt    integer      NOT NULL DEFAULT 3,
  err_code       varchar(32),
  err_msg        text,
  created_at     timestamptz  NOT NULL DEFAULT now(),
  CONSTRAINT etl_task_queue_pk PRIMARY KEY (task_id),
  CONSTRAINT etl_task_queue_uk UNIQUE (run_id, step_name),   -- 幂等入队护栏：同批次同步骤不可重复
  CONSTRAINT etl_task_queue_status_ck CHECK (status IN
    ('PENDING','CLAIMED','RUNNING','SUCCEEDED','FAILED','SKIPPED'))
);
CREATE INDEX idx_etl_task_queue_claim ON etl_task_queue (status, run_id, seq_no);
```

**状态流转（唯一合法路径）**

```
PENDING ──claim──> CLAIMED ──start──> RUNNING ──┬──> SUCCEEDED   (终态)
   ▲                                            └──> FAILED
   └────────── attempt < max_attempt 时重置 ─────────┘
FAILED (attempt >= max_attempt)  → 终态，阻塞后续依赖步骤
SKIPPED → 终态（依赖步骤已 FAILED 时由 worker 标记）
```

**执行契约（worker 必须遵守）**

| 编号 | 约定 |
|---|---|
| K1 | **领取（claim）—— 必须用下述形式，含两层并发防御**：<br>`UPDATE dw.etl_task_queue SET status='CLAIMED', claimed_by=:worker, claimed_at=now(), attempt=attempt+1 WHERE status='PENDING' AND task_id = (SELECT task_id FROM dw.etl_task_queue WHERE run_id=:run_id AND status='PENDING' AND (depends_on IS NULL OR depends_on IN (SELECT seq_no FROM dw.etl_task_queue WHERE run_id=:run_id AND status='SUCCEEDED')) ORDER BY seq_no LIMIT 1 FOR UPDATE SKIP LOCKED) RETURNING task_id, sql_text;`<br>⚠️ **两层防御都不可省（已实测）**：① 子查询的 `FOR UPDATE SKIP LOCKED` 让并发 worker 立即跳过被锁行（实测 1ms 返回 0 行，不阻塞）；② 外层 `status='PENDING'` 是锁释放后的复查。**若省略外层 `status` 条件会产生双重领取**：实测两个会话均成功领取同一 `task_id`，终态 `attempt=2`、`claimed_by` 被后者覆盖 —— 两个 worker 会并发执行同一任务 |
| K2 | **顶层提交**：worker 拿到 `sql_text` 后必须**作为顶层语句直接执行**（不得包在存储过程/匿名块内），否则 G13 生效、SMP 失效，O1 的唯一目的落空 |
| K3 | **SMP 设置**：执行前 `SET query_dop = :dop;`，执行后 `RESET query_dop;`（企业版/极简版；lite 下该设置无效但无害） |
| K4 | **幂等**：`sql_text` 内部必须自带 `DELETE 区间 + INSERT`（§5.3 幂等规则），因此**同一 task 重跑安全** |
| K5 | **去重**：`UNIQUE (run_id, step_name)` 保证 `PKG_ORCH` 重复入队不会产生重复任务；入队用 `INSERT ... ON DUPLICATE KEY UPDATE NOTHING` 语义（行存表，G16 不影响） |
| K6 | **重试**：`FAILED` 且 `attempt < max_attempt` → worker 下轮重新领取（K1 的 claim 语句需同时匹配 `status='FAILED' AND attempt<max_attempt`）；达到上限则终态 FAILED |
| K7 | **依赖阻塞**：某 task 终态 FAILED 时，其下游（`depends_on` 指向它的 `seq_no`）全部置 `SKIPPED`，本批次以非 0 退出码结束 |
| K8 | **超时回收**：`status IN ('CLAIMED','RUNNING')` 且 `claimed_at < now() - interval '2 hours'` 视为僵死，重置为 `PENDING`（worker 启动时执行一次回收） |
| K9 | **可观测**：每次状态变更由 `PKG_ETL_CORE` 以**自治事务**同步写 `etl_run_log`（主事务回滚后证据仍在，G5） |
| K10 | **退出码**：worker 在本批次全部 `SUCCEEDED` 时退出 0；存在终态 `FAILED`/`SKIPPED` 时退出非 0，供外部监控告警 |

> **归属**：表 DDL + 契约文档在 **Phase 0** 交付；`PKG_ORCH` 入队逻辑与外部 worker 在 **Phase 2** 交付。

### 5.4 C1 大屏的刷新可用性（G2 的处理）

`REFRESH MATERIALIZED VIEW CONCURRENTLY` 不支持（G2 实测），MV 刷新持排他锁阻塞读。方案：
1. C1 不用 MV。用 `ads_screen_store_today` **行存小表**（仅当日 × 有效门店，行数 = 门店数量级）。
2. `PKG_ADS.build_screen_today` 提供两种模式：`REPLACE`（DELETE 当日行 + INSERT）与
   `SWAP`（影子表构建后 RENAME 切换）。

**实测结论（V5 已解决）—— 小表场景 REPLACE 严格优于 SWAP**：

| 指标 | REPLACE | SWAP |
|---|---|---|
| 单轮耗时（50 轮均值） | **5.01 ms** | 9.68 ms（**1.93×**） |
| 并发读会话在刷新期间完成的读取次数 | **46** | 3 |
| 致命错误 | 0 | 0 |

⚠️ **原方案对 SWAP 的推理需要修正**：SWAP 并非"持锁时间总是更短"。它的优势来自把
**构建阶段**移出锁窗口，因此只在 `构建耗时 >> DDL 开销` 时才成立。小表上 SWAP 的
DDL 序列（`DROP` + `CREATE TABLE LIKE` + 2×`RENAME` + `DROP`）本身就有 4 次
AccessExclusiveLock，反而比 REPLACE 的行锁更阻塞读者（实测并发读 46 次 vs 3 次）。

**结论：默认 `REPLACE`。** 升级到 SWAP 的正确触发条件不是"表变大"，而是
**构建耗时 > 200ms**（届时构建开销才开始压过 DDL 开销）。

---

## 6. 增量抽取与水位线

### 6.1 前置修复（Phase 0，优先级高于报表体系）

| 编号 | 动作 | 理由 |
|---|---|---|
| F1 | `payment` **加 MAXVALUE 兜底分区** | S2：当前 `payment_date >= 2022-08-01` 插入直接报错，这是**写入可用性事故** |
| F2 | 补 4 个缺失索引：`payment(rental_id)`、`rental(customer_id)`、`rental(staff_id)`、`film_category(category_id)` | S6：有 FK 无索引，实测已出现 JOIN 键选错致 445K 中间结果膨胀（336ms） |
| F3 | 建 `ensure_partitions(p_months_ahead=>3)` 哨兵过程 | DD5；每日在管线**最前面**运行，DDL 失败即中止并告警 |

### 6.2 水位线设计（R2 规模下必须做真增量）

```sql
etl_watermark(
  source_name    varchar2(64) PRIMARY KEY,
  wm_type        varchar2(8),      -- 'ID' | 'TS'
  wm_id_value    bigint,           -- payment 用 payment_id
  wm_ts_value    timestamptz,      -- 其余 14 表用 last_update
  lookback_days  integer,          -- 回溯窗口
  safety_margin  interval,         -- 安全边界，默认 5 分钟
  last_run_id    varchar2(64),
  updated_at     timestamptz
)
```

| 表 | 水位线 | 说明 |
|---|---|---|
| `payment` | 主：`payment_id`（序列单调）**+ 叠加** `payment_date >= 水位线日 - lookback_days` 回溯窗口 | S3：无 `last_update`。单靠 `payment_id` 漏"id 更大但补录旧日期"；单靠 `payment_date` 漏同日并发插入 → **必须双轨** |
| `rental` | `last_update`（CDC）+ `return_date`（业务时间，归还/逾期指标） | S4 |
| 其余 13 表 | `last_update` | S4：触发器仅 BEFORE UPDATE，但 INSERT 走 `DEFAULT now()`，故对 INSERT+UPDATE 均有效 |

**安全边界**：水位线取值统一**减去 `safety_margin`（默认 5 分钟）**，规避"事务开始早于 `now()` 但提交晚于水位线采集"的漏行。

### 6.3 DELETE 检测（S4 的唯一解）

增量方案原理上无法检测物理删除（S4：DELETE 无痕迹）。方案：
- **每月一次全量键比对**：`SELECT pk FROM 源 MINUS SELECT pk FROM DWD`，差异写 `dq_check_result`（规则 `SRC_ROW_DELETED`）。
- **每月一次全量金额对账**：DWS 汇总 vs 源表直算逐月比对（规则 `RECON_L2_VS_BASE`，CRITICAL）。
- 迟到超出 `lookback_days` 的行由月度对账兜底。

### 6.4 迟到数据

`lookback_days`（payment 默认 7）+ `DELETE 区间 + INSERT` 覆盖。超窗由 §6.3 月度对账捕获。

---

## 7. openGauss 特有能力采用清单（对应 R3）

| # | 能力 | 用在哪 | 版本归属 | lite 可验证 |
|---|---|---|---|---|
| 1 | **列存表** `ORIENTATION=COLUMN, COMPRESSION=HIGH` | DWD/DWS 事实表 | 三版全有 | ✅ 实测可用 |
| 2 | **自适应压缩**（列存，默认 LOW→设 HIGH） | DWD/DWS | 三版全有 | ✅ |
| 3 | **行存透明页压缩** `compresstype=2(zstd), compress_level, compress_chunk_size` | DIM/ADS 行存表 | 三版全有 | 需实测 V6 |
| 4 | **RANGE 分区 + 显式 ADD PARTITION 哨兵** | DWD/DWS | 三版全有 | ✅ 实测可用 |
| 5 | **PACKAGE / PACKAGE BODY** | ETL 组织 | 三版全有 | ✅ 实测可用 |
| 6 | **`PRAGMA AUTONOMOUS_TRANSACTION`** | 审计留痕（失败仍持久化） | 三版全有 | ✅ 实测验证 |
| 7 | **`RAISE_APPLICATION_ERROR(-20xxx)`** | ETL 错误码体系 | 三版全有 | ✅ 实测可用 |
| 8 | **`MERGE INTO`**（含 `/*+ hint */`、指定分区、WHEN 子句带 WHERE） | 行存 DWS 月粒度回补 | 三版全有 | ✅ 实测幂等 |
| 9 | **全局临时表 GTT** `ON COMMIT PRESERVE ROWS` | ETL 行存中间结果 | 三版全有 | 需实测 V8；**G17：不支持并行/列存/分区** |
| 10 | **Plan Hint** `leading/rows/use_hash/no_expand/OPT_PARAM` | 固化报表 SQL 计划 | 三版全有 | ✅ |
| 11 | **SQL PATCH** `DBE_SQL_UTIL.create_hint_sql_patch` | 不改 SQL 稳定计划 | 三版全有 | ✅ 实测 schema 存在(G9)；需 `enable_resource_track` + `instr_unique_sql_count>0`（实测=100） |
| 12 | **HyperLogLog** | C1 大屏近似 UV | 三版全有 | 需实测 V9 |
| 13 | **多列统计** `ALTER TABLE ... ADD STATISTICS ((stat_date, store_id))` | DWD/DWS 组合谓词 | 三版全有 | 需实测 V10 |
| 14 | **Ustore** `WITH (STORAGE_TYPE=USTORE)` | 频繁 UPDATE 的 DWS 月表 | 三版全有 | ✅ `enable_ustore=on`(G11) |
| 15 | **Oracle 兼容分析语法** `LISTAGG ... WITHIN GROUP`、`CONNECT BY`、`ROWNUM`、`NVL`、`DECODE` | 报表 SQL | 三版全有 | 需实测 V11 |
| 16 | **`GROUPING SETS`/`CUBE`/`ROLLUP` + `GROUPING()`** | C2 多粒度下钻 | 三版全有 | ✅ 实测可用 |
| 17 | **`FILTER (WHERE ...)`** 条件聚合 | 各层指标 | — | ✅ **实测可用（修正文档）** |
| 18 | **窗口函数全集** `LAG/LEAD/RANK/DENSE_RANK/NTILE/FIRST_VALUE/LAST_VALUE/SUM OVER + ROWS/RANGE frame` | C3 环比/趋势/TOP N | 三版全有（**列存表受限见 V7**） | ✅ 实测可用 |
| 19 | **`DBE_PERF` / `gs_asp` / `statement_history`** | 管线可观测性 | 三版全有（lite 采集线程被阉割，G42） | ⚠️ **lite 实测不可用**：参数 on 但 `gs_asp`/`statement_history` 均 0 记录（G42）；企业版需授 `monadmin` |
| 20 | **`gs_probackup`** 物理备份 | C4 披露期数据冻结留存 | 三版全有 | 需实测 V12 |
| 21 | **`PKG_SERVICE.JOB_SUBMIT`** | 备用库内调度（主用外部触发） | 三版全有 | ✅ 实测 job 提交/取消成功(G10) |
| 22 | *(增强，企业/极简版)* **SMP `query_dop`** | 重型聚合加速 | 企业版/极简版 | ❌ lite 不可（G13 另限过程内） |
| 23 | *(增强，企业/极简版)* **LLVM/Codegen、行存转向量化 `try_vector_engine_strategy`** | 表达式密集查询加速 | 企业版/极简版 | ❌ lite 不可 |

**明确不采用**：
- ❌ **IMMV 增量物化视图**（G14：全版本不支持聚合）
- ❌ **二级分区 SUBPARTITION**（G15：仅行存 + 不支持 MERGE/UPSERT，与 DD2/DD6 冲突）
- ❌ **`ON DUPLICATE KEY UPDATE`**（G16：列存不支持）
- ❌ **MOT / HTAP 行列融合 / postgres_fdw / PL/Java**（lite 无，且非必需）

---

## 8. 造数与验证方案（对应 R6 / R7：先功能、后性能）

### 8.1 三层造数策略（DD11）

| 层 | 目的 | 工具 | 规模 | 何时用 |
|---|---|---|---|---|
| **T1 确定性夹具** | **功能正确性断言**（ground truth 已知） | 纯 SQL（`generate_series` + 固定值 + `setseed`） | 千~万行 | Phase 1-2，每次回归 |
| **T2 分布真实性** | 回归测试的数据真实感 | **SDV `GaussianCopulaSynthesizer`（单表）** | 十万~百万行 | Phase 3 |
| **T3 规模压力** | 性能压测 | 纯 SQL `INSERT...SELECT generate_series` | 1000 万~1 亿行 | Phase 4（性能阶段） |

**为什么 SDV 不能承担 T1/T3**（官方依据）：
- SDV 团队原话：公开版 `HMASynthesizer` "**is not meant for scale. It is only designed to handle simple schemas for small amounts of data (as proof-of-concept)**"（[Issue #2110](https://github.com/sdv-dev/SDV/issues/2110)）
- 官方文档：HMA "optimized for smaller datasets with around **5 tables and 1 level of depth**"（[HMASynthesizer](https://docs.sdv.dev/sdv/modeling/multi-table-synthesizers/hmasynthesizer)）→ Pagila 是 15 表多层
- 多表 `sample()` **只有 `scale` 参数、无 `batch_size`**，全部 DataFrame 驻留内存（[Sample Realistic Data](https://docs.sdv.dev/sdv/sampling/sample-realistic-data.md)）
- 免训练的 `DayZSynthesizer`、可扩展的 `HSA`/`Independent` 均为 **Enterprise 付费**（[Compare Features](https://docs.sdv.dev/sdv/explore/sdv-enterprise/compare-features.md)）
- **SDV 值不可预知** → 无法写"期望值断言"，不适合正确性验证
- **时间范围锁死**：`enforce_min_max_values=True` 默认使合成 `payment_date` 不超出种子数据范围（现为 7 个月）；跨年扩展需 Enterprise Targeted Sampling

**SDV 在本方案中的确切定位（T2）**：
- 用 `GaussianCopulaSynthesizer` **对单表**（`payment.amount` 分布、`film` 属性分布、`customer` 属性分布）分别建模
- 约束用 `Inequality(low='rental_date', high='return_date')`（官方支持 datetime）
- 输出 CSV（`output_file_path` + `batch_size`）→ `COPY` / `gs_bulkload` 入库
- **外键由 SQL 侧按构造补齐**（引用已生成父表主键），不依赖 HMA
- 许可证：**BUSL-1.1**（非 MIT），Additional Use Grant 允许生产使用，仅禁止"作为合成数据服务对外商业提供"；内部测试造数在授权范围内。**建议法务过一眼**（§10-Q4）

### 8.2 覆盖率目标（功能验证的核心）

造数必须**显式覆盖**以下边界，每条对应一个断言用例：

| 编号 | 覆盖点 | 对应缺陷/约束 |
|---|---|---|
| CV1 | 有效门店 / 休眠门店 / 无效门店 三态 | D1/D2/D3 |
| CV2 | `rental` 日期超出 `payment` 日期范围 | D4 |
| CV3 | 首月/末月不完整期间 | D6 |
| CV4 | 分区边界日期（月末 23:59:59.999 与月初 00:00:00，UTC） | S1/S8 |
| CV5 | 跨月补录（`payment_id` 更大但 `payment_date` 更早） | S3 双轨水位线 |
| CV6 | 源侧 DELETE（删除已进 DWD 的行） | S4/§6.3 |
| CV7 | `return_date IS NULL`（在租）与逾期 | 业务指标 |
| CV8 | 空字符串 / NULL（`phone`/`district`）在拼接与 `COUNT` 中的行为 | A 模式空串≡NULL |
| CV9 | 金额边界：`amount` 接近 999.99；汇总值远超 999.99 | S5/G4 |
| CV10 | 同一天并发插入（水位线安全边界） | §6.2 |
| CV11 | 无 `staff` 的门店产生交易 | D3 |
| CV12 | 悬空 `manager_staff_id` | D5 |
| CV13 | 跨年数据（≥ 25 个月）以支持 YoY | G8 |
| CV14 | 迟到超 `lookback_days` 的数据 | §6.4 |

### 8.3 同比环比的现实约束（G8）

现有数据仅 2022-01~07（7 个月），实测 `LAG(amt,12)` 返回**全 NULL** → **YoY 在现有数据下无法计算**。

- 造数必须生成 **≥ 25 个月**跨度（CV13），否则 YoY 无法验证。
- **禁止 `COALESCE(prev_year, 0)`** —— 会产出 `+∞%`/`-100%`，进入披露文件即灾难。
- 除法一律 `NULLIF(denom, 0)`。
- **MoM 两个必踩坑**（实测证实第 2 个）：
  1. **缺月错位**：某店某月无交易时 `LAG` 会取到更早月份 → 必须先生成「完整月份骨架 × 有效门店」再 `LEFT JOIN` 事实后 `LAG`。
  2. **首末月不完整**：实测 2022-02 相对 2022-01 的 MoM = **+228.46%**（因 1 月仅 23–31 日、723 笔），2022-07 = **−11.08%**（仅到 27 日）→ DWS 必须带 `is_complete_period` 标志，MoM 在不完整月返回 NULL。

### 8.4 功能验证方法（R7：先功能）

| 层 | 验证方式 | 通过标准 |
|---|---|---|
| 幂等性 | 同参数连续跑 3 次 | 行数与各指标金额**完全一致** |
| 增量正确性 | 增量跑 vs 全量重算 | 逐分区逐维度**指标完全一致** |
| 对账 | DWS 汇总 vs 源表直算 | 逐月金额/笔数**完全一致** |
| DQ 规则 | 注入每类缺陷 | 对应规则命中且 severity 正确 |
| 分区裁剪 | `EXPLAIN` 断言 | 半开区间查询 `Iterations: 1`；`EXTRACT()` 包裹时全扫（反例） |
| 披露不可变 | `UPDATE`/`DELETE` 快照表 | **必须报错** |
| 重算一致 | 同期间 `recompute_period` 两次 | 指标值一致；`snapshot_version` 递增；不覆盖旧行 |
| 指纹告警 | 改一行源数据后重采指纹 | 指纹不匹配并写 `dq_check_result` |
| 口径拦截 | 查询门店总数 | 返回**有效门店数**，非 `count(*) FROM store` |

---

## 9. 分阶段实施计划

> 遵循 R7：Phase 0-3 为功能，Phase 4 才是性能。

### Phase 0 — 止血与地基
**交付物**
1. F1 `payment` MAXVALUE 兜底分区
2. F2 4 个缺失索引
3. F3 `PKG_ETL_CORE.ensure_partitions` 哨兵过程
4. 旁路表：`etl_run_log`、`etl_watermark`、`dq_check_result`
5. **`etl_task_queue` 表 DDL + 执行契约文档**（§5.3.1，O1 架构的接口基础）
6. **口径基线文档**：有效门店定义、统一分析截止日、`COUNT` 口径（`COUNT(*)` vs `COUNT(col)` 在 A 模式下不同）、时区口径（UTC）

**QA 场景（可执行）**

| # | 目的 | 命令 | 预期结果 / 判定 |
|---|---|---|---|
| Q0.1 | 兜底分区生效 | `docker exec pagila gsql-pagila -f /tmp/qa-phase0.sql`（内含 `BEGIN; INSERT ... payment_date='2099-01-01'; SELECT CASE WHEN count(*)=1 THEN 'PASS' ...; ROLLBACK;`）<br>⚠️ **必须用 `-f` 文件形式**：`gsql -c "多条语句"` 只输出最后一条结果，断言不可观测 | 输出 `Q0.1 PASS`。修复前同脚本必报 `inserted partition key does not map to any table partition` |
| Q0.2a | 4 个索引存在 | `docker exec pagila gsql-pagila -t -c "SELECT count(*) FROM pg_indexes WHERE schemaname='public' AND indexname IN ('idx_fk_payment_rental_id','idx_fk_rental_customer_id','idx_fk_rental_staff_id','idx_fk_film_category_category_id');"` | **= 4** |
| Q0.2b | 每个索引**可被优化器使用** | 对每个索引各跑一次选择性谓词 EXPLAIN，例：`EXPLAIN (COSTS OFF) SELECT * FROM payment WHERE rental_id=100;`<br>`rental.staff_id` 例外：当前演示数据仅 2 个不同值/16044 行，Seq Scan 是**优化器正确决策**，故用 Plan Hint 解耦验证：`EXPLAIN (COSTS OFF) SELECT /*+ indexscan(rental idx_fk_rental_staff_id) */ * FROM rental WHERE staff_id=1;` | 计划中出现**对应索引名**（如 `Partitioned Bitmap Index Scan on idx_fk_payment_rental_id`、hint 例出现 `Index Scan using idx_fk_rental_staff_id`）<br>⚠️ **不可断言"不出现 Seq Scan"**：小数据量/低选择性下优化器选全扫与索引可用性无关；`rental_id` 非分区键故 `Iterations: <全部>` 属正常 |
| Q0.3 | 分区哨兵幂等 | `docker exec pagila gsql-pagila -c "CALL dw.pkg_etl_core.ensure_partitions('payment',3);"` 连续 2 次，比对分区数 | 第 2 次 `created 0 partition(s)`，分区数不变。补充断言：`payment_pmax` 仍能接住远期行（插 `2099-01-01` 落在 pmax）、当月行正确路由到自己的月分区 |
| Q0.4 | `etl_task_queue` 入队去重（K5） | `docker exec pagila gsql-pagila -f /tmp/qa-phase0.sql`（含两次同键 INSERT + 一次 `ON DUPLICATE KEY UPDATE NOTHING`） | 第 2 条**报唯一约束冲突** `etl_task_queue_uk`；第 3 条 `INSERT 0 0` 且 `sql_text` 未被改写 → 输出 `Q0.4 PASS` |
| Q0.5 | 并发原子领取（K1） | `bash sqls/dw/tests/qa-phase0-concurrent.sh fixed`<br>反例复现：`bash sqls/dw/tests/qa-phase0-concurrent.sh naive` | `fixed` → `Q0.5 PASS (single claim by A, attempt=1)`，并发者 1ms 返回 0 行（`SKIP LOCKED` 未阻塞）<br>`naive` → `Q0.5 FAIL (attempt=2, claimed_by=B)`，证明**两层防御缺一不可** |
| Q0.6 | 自治事务审计留痕 | `docker exec pagila gsql-pagila -f /tmp/qa-phase0.sql`（内含临时过程 `dw.qa_fail_demo`：`log_start` → 业务写入 → `RAISE_APPLICATION_ERROR(-20099)` → `EXCEPTION` 中 `log_end` 后 `RAISE`） | 命令**报 ORA-20099 退出**，但 `etl_run_log` 中该 `run_id` 的 `FAILED` 记录 **=1**，且业务写入的 `dq_check_result` 行 **=0**（已回滚）→ 输出 `Q0.6 PASS` |

**验收标准**：Q0.1~Q0.6 全部通过；口径文档经**人工签字确认**。

---

### Phase 1 — 造数与 DIM/DWD
**交付物**
1. T1 确定性夹具脚本，覆盖 CV1~CV14 全部 14 项，跨度 ≥ 25 个月
2. `dim_store`（含 `store_status` 三态）/ `dim_staff` / `dim_film` / `dim_geo` + `PKG_DIM`
3. `dwd_fact_payment` / `dwd_fact_rental`（列存 + RANGE 月分区 + 维度退化）+ `PKG_DWD`
4. `PKG_DQ` + DQ 规则集（见 §附录 A）
5. 水位线双轨逻辑（payment `ID`+`TS`）
6. `tests/sql/cv_assertions.sql`：CV1~CV14 逐项断言脚本

**QA 场景（可执行）**

| # | 目的 | 命令 | 预期结果 / 判定 |
|---|---|---|---|
| Q1.1 | 覆盖率断言全绿 | `docker exec pagila gsql-pagila -f /tests/sql/cv_assertions.sql` | 输出 14 行，每行形如 `CV01 | PASS`；**任何 `FAIL` 即阻塞**。脚本内每项用 `CASE WHEN count(*)>0 THEN 'PASS' ELSE 'FAIL' END` |
| Q1.2 | 跨度满足 YoY | `docker exec pagila gsql-pagila -t -c "SELECT count(DISTINCT date_trunc('month',payment_date)) AS months FROM payment;"` | `months >= 25`（CV13） |
| Q1.3 | DWD 幂等（3 次） | `for i in 1 2 3; do docker exec pagila gsql-pagila -c "CALL PKG_DWD.build_dwd_fact_payment(date '2024-03-01', date '2024-04-01','R$i',false,NULL,NULL);"; done && docker exec pagila gsql-pagila -c "SELECT count(*) c, round(sum(amount),2) s FROM dwd_fact_payment WHERE stat_date>='2024-03-01' AND stat_date<'2024-04-01';"` | 3 次执行后 `c` 与 `s` 与**单次执行结果完全一致**（逐字节比较输出） |
| Q1.4 | 增量 vs 全量一致 | ① 全量：`CALL PKG_DWD.build_dwd_fact_payment('2024-01-01','2025-01-01',...)` → 存基线到 `tmp_full`；② 清空后按月循环增量 12 次；③ 比对 | `SELECT count(*) FROM (SELECT * FROM tmp_full EXCEPT SELECT * FROM dwd_fact_payment) t;` **= 0** 且反向 `EXCEPT` 也 **= 0** |
| Q1.5 | 门店口径拦截（RK1） | `docker exec pagila gsql-pagila -t -c "SELECT count(*) FROM dim_store WHERE store_status='ACTIVE';"` 与 `SELECT count(*) FROM store;` | 前者 = 造数中设定的有效门店数；后者 = 全量行数；**两者必须不同**，证明口径已分离 |
| Q1.6 | DQ 规则注入命中 | 逐条注入：`BEGIN; DELETE FROM staff WHERE store_id=<有业务门店>; CALL PKG_DQ.run_all('R_DQ'); SELECT rule_code,severity FROM dq_check_result WHERE run_id='R_DQ'; ROLLBACK;` | 命中 `STORE_NO_STAFF` 且 `severity='CRITICAL'`。对 12 条规则各做一次，**每条都必须命中且 severity 正确** |
| Q1.7 | 分区裁剪生效（正例） | `docker exec pagila gsql-pagila -c "EXPLAIN (COSTS OFF) SELECT sum(amount) FROM dwd_fact_payment WHERE stat_date>='2024-03-01' AND stat_date<'2024-04-01';"` | 出现 `Iterations: 1`（或 `Selected Partitions: N..N` 单分区） |
| Q1.8 | 分区裁剪失效（反例，防回归） | `docker exec pagila gsql-pagila -c "EXPLAIN (COSTS OFF) SELECT sum(amount) FROM dwd_fact_payment WHERE EXTRACT(MONTH FROM stat_date)=3;"` | 出现 `Iterations: <全部分区数>` —— 确认反模式确实有害，作为文档化反例保留 |
| Q1.9 | 水位线双轨（CV5 补录） | 插入 `payment_id` 最大但 `payment_date` 为上月的行 → 跑增量 | 该行**出现在 DWD 对应月分区**中（证明 `payment_date` 回溯窗口生效，单靠 `payment_id` 会归错月） |
| Q1.10 | 列存表建表形态 | `docker exec pagila gsql-pagila -t -c "SELECT reloptions FROM pg_class WHERE relname='dwd_fact_payment';"` | 包含 `orientation=column` 与 `compression=high` |

**验收标准**：Q1.1~Q1.10 全部通过。

---

### Phase 2 — DWS + C1/C2/C3
**交付物**
1. `dws_sales_day_store_category` / `dws_sales_day_store_staff` / `dws_rental_day_store`（列存分区）
2. `dws_sales_month_store`（行存 + Ustore）
3. `PKG_DWS` + `PKG_ADS`
4. C1 `ads_screen_store_today` + 影子表切换
5. C2 `v_ads_ops_*`（GROUPING SETS + GROUPING()）
6. C3 `v_ads_exec_*`（月份骨架 + LAG + `is_complete_period`）
7. `PKG_ORCH.run_daily` / `run_monthly` / `run_screen` + **`etl_task_queue` 入队逻辑**
8. **外部 worker 脚本** `scripts/etl_worker.sh`（实现 K1~K10）+ cron/CronJob 配置

**QA 场景（可执行）**

| # | 目的 | 命令 | 预期结果 / 判定 |
|---|---|---|---|
| Q2.1 | DWS 幂等（3 次） | 同 Q1.3 模式，对 `PKG_DWS.build_dws_sales_day_store_category` | 3 次后行数与金额与单次一致 |
| Q2.2 | 逐月对账（RECON） | `docker exec pagila gsql-pagila -c "SELECT d.stat_month, d.amt AS dws, b.amt AS base, d.amt-b.amt AS diff FROM (SELECT date_trunc('month',stat_date) stat_month, sum(amount) amt FROM dws_sales_day_store_category GROUP BY 1) d FULL JOIN (SELECT date_trunc('month',payment_date), sum(amount) FROM payment GROUP BY 1) b(stat_month,amt) USING (stat_month) WHERE coalesce(d.amt,0)<>coalesce(b.amt,0);"` | **返回 0 行**（无差异） |
| Q2.3 | MoM 在不完整月返回 NULL | `docker exec pagila gsql-pagila -c "SELECT stat_month, is_complete_period, mom_rate FROM v_ads_exec_month ORDER BY stat_month LIMIT 3;"` | 首月 `mom_rate IS NULL`；`is_complete_period=false` 的月份 `mom_rate IS NULL` |
| Q2.4 | 缺月不错位 | 造数删除某店某月全部交易后查 C3 | 该店该月出现在结果中（骨架 LEFT JOIN 生效）且 `amt=0`/`NULL`；**下一月的 `prev_amt` 指向被删月而非更早月** |
| Q2.5 | YoY 可算（25 月数据） | `docker exec pagila gsql-pagila -t -c "SELECT count(*) FROM v_ads_exec_month WHERE yoy_rate IS NOT NULL;"` | **> 0**（对比 G8：7 个月数据时此值为 0） |
| Q2.6 | GROUPING() 小计标识 | `docker exec pagila gsql-pagila -c "SELECT store_id, GROUPING(store_id) g, sum(amt) FROM dws_sales_day_store_category GROUP BY ROLLUP(store_id) ORDER BY g DESC LIMIT 3;"` | 存在 `g=1` 的总计行且其 `store_id IS NULL` |
| Q2.7 | **C1 影子表切换读不中断** | 会话 A：`while true; do docker exec pagila gsql-pagila -t -c "SELECT count(*) FROM ads_screen_store_today;" >> /tmp/reads.log 2>>/tmp/reads.err; done &`；会话 B：`for i in $(seq 1 20); do docker exec pagila gsql-pagila -c "CALL PKG_ADS.build_ads_screen_today();"; done`；结束后检查 | `/tmp/reads.err` **无 `relation ... does not exist` 且无 `could not obtain lock`**；`/tmp/reads.log` 行数 > 0 且无空值 |
| Q2.8 | 失败后重跑无重复 | ① 启动 `PKG_DWS.build_dws_sales_day_store_category` 后 `docker exec pagila gsql-pagila -c "SELECT pg_terminate_backend(<pid>);"` 中断；② 原参数重跑；③ 校验 | 重跑后行数/金额 = 正常单次结果；**无重复行**（`SELECT count(*) FROM (SELECT stat_date,store_id,category_id,count(*) c FROM dws_... GROUP BY 1,2,3 HAVING count(*)>1) t;` = 0） |
| Q2.9 | worker 顶层提交（K2） | `bash scripts/etl_worker.sh --run-id R_TEST --dry-run` | 输出的执行方式为 `gsql -c "<sql_text>"` 顶层语句；**不包含** `CALL`/`DO`/`BEGIN...END` 包裹 |
| Q2.10 | worker 依赖阻塞与退出码（K7/K10） | 入队 3 个 task（seq 1,2,3；3 依赖 2），令 seq2 的 `sql_text` 为 `SELECT 1/0`，运行 worker | seq1=`SUCCEEDED`；seq2=`FAILED` 且 `attempt=max_attempt`；seq3=`SKIPPED`；`echo $?` **非 0** |
| Q2.11 | worker 超时回收（K8） | 手工置一条为 `CLAIMED` 且 `claimed_at=now()-interval '3 hours'`，启动 worker | 该条被重置为 `PENDING` 后正常执行完成 |
| Q2.12 | 重试（K6） | 入队一条前 2 次必败第 3 次成功的 `sql_text`（借计数表实现），`max_attempt=3` | 最终 `status='SUCCEEDED'`，`attempt=3` |

**验收标准**：Q2.1~Q2.12 全部通过。

---

### Phase 3 — C4 披露层 + SDV 分布真实性
**交付物**
1. `rpt_period_close` / `rpt_metric_def` / `rpt_source_fingerprint` / `rpt_disclosure_snapshot`（+ 不可变触发器）
2. `PKG_DISCLOSE.take_fingerprint` / `close_period` / `recompute_period`
3. CRITICAL 硬闸门（0 CRITICAL 才允许 `close_period`）
4. T2：SDV `GaussianCopulaSynthesizer` 单表建模脚本 `scripts/sdv_gen.py` + CSV → `COPY` 入库流程
5. `gs_probackup` 冻结备份流程（验证 V12 后）

**QA 场景（可执行）**

| # | 目的 | 命令 | 预期结果 / 判定 |
|---|---|---|---|
| Q3.1 | 快照不可变（UPDATE） | `docker exec pagila gsql-pagila -c "UPDATE rpt_disclosure_snapshot SET metric_value=0 WHERE period='2024-12';"` | **报错**（触发器 RAISE），`echo $?` 非 0 |
| Q3.2 | 快照不可变（DELETE） | `docker exec pagila gsql-pagila -c "DELETE FROM rpt_disclosure_snapshot WHERE period='2024-12';"` | **报错**，`echo $?` 非 0 |
| Q3.3 | 重算一致且版本递增 | `docker exec pagila gsql-pagila -c "CALL PKG_DISCLOSE.recompute_period('2024-12');"` 执行 2 次后 `SELECT snapshot_version, metric_code, metric_value FROM rpt_disclosure_snapshot WHERE period='2024-12' ORDER BY snapshot_version, metric_code;` | 出现 `snapshot_version` 1,2,3 三组；**同 `metric_code` 各版本 `metric_value` 完全一致**；旧行未被覆盖（`count(*)` 随版本递增） |
| Q3.4 | 指纹告警 | ① `CALL PKG_DISCLOSE.take_fingerprint('2024-12');` ② `BEGIN; UPDATE payment SET amount=amount+1 WHERE payment_id=(SELECT min(payment_id) FROM payment WHERE payment_date>='2024-12-01' AND payment_date<'2025-01-01');` ③ 再 `take_fingerprint` 并比对 ④ `ROLLBACK;` | 第 2 次指纹的 `sum_amount`/`checksum` 与第 1 次**不同**，且 `dq_check_result` 出现 `FINGERPRINT_MISMATCH`（CRITICAL） |
| Q3.5 | CRITICAL 硬闸门 | `docker exec pagila gsql-pagila -c "INSERT INTO dq_check_result(run_id,period,rule_code,severity) VALUES ('R_G','2024-12','STORE_NO_STAFF','CRITICAL'); CALL PKG_DISCLOSE.close_period('2024-12');"` | `close_period` **报错拒绝**；`SELECT status FROM rpt_period_close WHERE period='2024-12';` **不等于** `CLOSED` |
| Q3.6 | 闸门不对称（C2/C3 仍可用） | 同上存在 CRITICAL 时查 `v_ads_ops_*` | 正常返回数据，且结果集含 `dq_flag` 列且值为 true（带瑕疵可用） |
| Q3.7 | SDV 约束成立 | `python3 scripts/sdv_gen.py --table rental --rows 100000 --out /tmp/rental.csv` 后入库并校验 | `SELECT count(*) FROM stg_rental WHERE return_date IS NOT NULL AND return_date <= rental_date;` **= 0**（`Inequality` 约束 100% 成立） |
| Q3.8 | SDV 入库路径可用 | `docker exec pagila gsql-pagila -c "\copy stg_rental FROM '/tmp/rental.csv' WITH CSV HEADER"` | 导入行数 = CSV 行数，无报错 |

**验收标准**：Q3.1~Q3.8 全部通过。

---

### Phase 4 — 性能（仅在功能全部通过后启动）
**交付物**
1. T3 规模造数：payment 1000 万 → 1 亿行
2. 企业版/极简版环境（**G37：需 x86_64 Linux 或鲲鹏等完整 ARM 服务器；Apple Silicon Docker 不可用**）
3. SMP (`query_dop`) / 列存向量化 / 多列统计 / 行存压缩 的实测收益报告
4. §10 全部 V 项实测结论
5. Plan Hint + SQL PATCH 计划固化
6. 容量与阈值基线（写回 §11）

**QA 场景（可执行）**

| # | 目的 | 命令 | 预期结果 / 判定 |
|---|---|---|---|
| Q4.1 | 规模达标 | `docker exec pagila gsql-pagila -t -c "SELECT count(*) FROM payment;"` | ≥ 10,000,000（第一档）/ 100,000,000（第二档） |
| Q4.2 | **V1：过程内 vs 顶层的 SMP 差异**（决定 Q2） | 企业版环境：① 顶层 `SET query_dop=4; EXPLAIN (ANALYZE) INSERT INTO ... SELECT ...`；② 同一 SQL 包在存储过程内 `EXECUTE IMMEDIATE` 执行并 `EXPLAIN` | ① 计划含 `Local Gather`/`dop: 1/4`；② 若**不含**则 G13 对 `EXECUTE IMMEDIATE` 同样生效 → 采用 O1；若含则可采用 O3。**结论必须写入方案** |
| Q4.3 | V2：lite 的 query_dop 是否真并行 | lite 环境：`SET query_dop=4; EXPLAIN SELECT count(*) FROM payment;` | 记录是否出现 `dop` 相关算子，解决矩阵矛盾（§10-U1） |
| Q4.4 | V3：列存向量化算子 | `EXPLAIN SELECT store_id,sum(amt) FROM dwd_fact_payment GROUP BY store_id;` | 记录是否出现 `Vector*` 系列算子 |
| Q4.5 | V7：列存窗口函数范围 | 在列存表上逐个执行 `LAG`/`SUM OVER`/`ROWS BETWEEN` | 记录每个是否成功；与文档"仅 rank/row_number"对照 |
| Q4.6 | V6：行存压缩收益 | 建 `compresstype=2` 与未压缩两份同数据表，查 `compress_ratio_info` 与写入耗时 | 压缩率与写入开销数值报告 |
| Q4.7 | V10：多列统计收益 | `ADD STATISTICS ((stat_date, store_id))` 前后对比 `EXPLAIN` 估算行数 vs 实际行数 | 估算误差显著缩小 |
| Q4.8 | 大屏 P95 | 循环 200 次 C1 查询并统计耗时 | 记录 P95 基线；若 > 500ms 触发 §11 升级动作 |
| Q4.9 | ETL 端到端基线 | `time bash scripts/etl_worker.sh --run-id R_PERF` | 记录 1 亿行下 `run_daily` 总耗时；若串行 > 30 分钟触发企业版 SMP（§11） |

**验收标准**：Q4.1~Q4.9 全部产出**数值报告**；V1（Q4.2）必须给出 O1/O3 的明确结论并回写 §5.3 与 §10-Q2。

---

## 10. 未决问题与需实测项

### 10.1 需用户决策（Q）

| 编号 | 问题 | 选项 | 影响 | 建议 |
|---|---|---|---|---|
| **Q1** | 部署版本最终选型 | (a) 企业版；(b) **极简版**（有 SMP/LLVM/向量化/HTAP，无 CM/OM）；(c) lite | 决定能否用 SMP/向量化加速；极简版是被忽略的中间选项 | 若不需自动故障切换 → **极简版**性价比最高 |
| **Q2** | §5.3 的 O1/O2/O3 选哪个 | O1 外部提交顶层语句（保 SMP）/ O2 纯过程内串行 / O3 `EXECUTE IMMEDIATE`（待验证） | **G13 决定这是本方案最大架构张力** | 先验 V1，若 O3 可行则 O3，否则 O1 |
| **Q3** | 是否需要数仓与业务库**物理隔离** | 同实例（本方案）/ 独立实例+ODS 层 | 决定是否需补 ODS 层 | 同实例起步，写入升级阈值 |
| **Q4** | SDV BUSL-1.1 许可证是否需法务确认 | 需要 / 不需要 | 合规风险 | 内部测试用途在授权内，建议走一次法务 |
| **Q5** | 门店有效性口径的**业务定义**由谁签字 | — | D1 直接威胁 C4 披露合规（"500 家门店"进入公开文件是实质性错误陈述） | **必须业务方书面确认** |
| **Q6** | 是否需补 2021 及更早历史数据以支持真实 YoY | 补 / 不补（造数模拟） | G8：现有 7 个月无法算 YoY | 生产上必须补；验证阶段用造数 |

### 10.2 需实测验证（V）

> **状态更新（2026-08-27）**：V2~V13 已在 lite 上全部实测完成，结论见
> `sqls/dw/docs/phase4-baseline.md`。仅 V1 / V14 / V15 仍需企业版或更大内存主机。
> 其中 **V1 是决定 §5.3 用 O1 还是 O3 的唯一依据**。

| 编号 | 待验证 | 为什么重要 | 验证方法 |
|---|---|---|---|
| **V1** | 存储过程内 `EXECUTE IMMEDIATE` 执行的重型 SQL 是否仍受 G13（无 SMP）限制 | 决定 Q2 | 企业版/极简版环境下 `SET query_dop=4`，对比过程内外 `EXPLAIN` 是否出现 `Local Gather ... dop` |
| **V2** | lite 的 `query_dop` 是否真正起并行线程 | 官方矩阵自相矛盾（SMP 并行查询 ❌ vs SMP并行执行 ✔） | `SET query_dop=4; EXPLAIN SELECT count(*) FROM 大表;` |
| **V3** | lite 列存查询是否出现向量化算子 | 矩阵"向量化引擎 ❌"与"行列混合存储 ✔"矛盾 | `EXPLAIN` 观察是否有 `Vector Sonic Hash Agg` 等算子 |
| **V4** | **列存表 + INTERVAL 自动分区**组合是否可用 | 若可用则 DD5 可简化 | 建列存 INTERVAL 分区表并插入跨月数据 |
| **V5** | C1 小表重建耗时 | 决定是否需要影子表切换（§5.4） | 在目标规模门店数下计时 |
| **V6** | 行存压缩 `compresstype=2` 实际压缩率与写入开销 | 采用与否 | 建表对比 `compress_ratio_info` |
| **V7** | **列存表窗口函数实际支持范围** | 实测 `sum() OVER` 可用但文档称仅 `rank`/`row_number` —— 冲突 | 在列存表上逐个测 `LAG`/`SUM OVER`/frame |
| **V8** | GTT `ON COMMIT PRESERVE ROWS` 在 lite 可用性 | ETL 中间结果载体 | 建 GTT 并跨事务验证 |
| **V9** | HyperLogLog 在 lite 可用性与精度 | C1 近似 UV | `hll` 类型建表并对比精确 distinct |
| **V10** | 多列统计 `ADD STATISTICS` 对组合谓词的选择率改善 | DWD/DWS 谓词 | 加统计前后对比 `EXPLAIN` 估算行数 |
| **V11** | `LISTAGG`/`CONNECT BY`/`ROWNUM`/`NVL`/`DECODE` 在 lite 可用性 | 报表 SQL 写法 | 逐个执行 |
| **V12** | `gs_probackup` 在容器内可用性 | C4 冻结备份 | 执行一次全备+恢复 |
| **V13** | `ANALYZE table PARTITION(名)` 在 7.0 是否真正收集单分区统计 | G19 称语法支持但功能不支持 | 对比 `pg_stats` 变化 |
| **V14** | 企业版镜像可启动性 | **已实测：无法启动，根因非内存**。曾以为 12GB 内存不足所致；用 `OTHER_PG_CONF` 压到 2GB 后仍失败，真因是 **`libkvecturbo.so`（向量加速库）要求宿主 CPU 具备 Docker VM 缺失的特性（Apple Silicon 虚拟化无 SVE 等），报 `KVecturbo: ... please check CPU architect` 后 gaussdb 退出**。结论：需 x86_64 Linux 或完整 ARM 服务器（如鲲鹏） |
| **V15** | `DBE_SCHEDULER` 在企业版/极简版的实际可用性 | 备选调度方案 | 检查 schema 与函数 |

---

### 10.3 实施期实测补充（Phase 0–3 执行中新增，已回写代码）

### 已解决的 V 项

| 编号 | 结论 |
|---|---|
| **V3 已解决** | **lite 上列存查询确实走向量化算子**。实测计划：`Row Adapter → Vector Aggregate → Vector Partition Iterator → Partitioned CStore Scan`。官方矩阵"向量化引擎 ❌ 轻量版"与实测矛盾，**以实测为准**（矩阵内部也自相矛盾，见 §10.2-U1） |
| **V6 已解决** | 行存 `compresstype=2(zstd)` 可用。高重复数据上 116 kB vs 11 MB（≈97×，属上限非代表值） |
| **V7 部分解决** | 列存表上 `sum() OVER (PARTITION BY)` 实测可用，与文档"仅 rank/row_number"矛盾。完整 frame 支持待 Phase 4 逐项测 |

### 新增实测硬约束（均已在代码中规避）

| 编号 | 约束 | 影响与规避 |
|---|---|---|
| **G21** | **列存表不支持 `SPLIT PARTITION`**（`column-store relation doesn't support this ALTER yet`） | 哨兵新增路径 C：`DROP pmax → ADD 月分区 → 重建 pmax`（要求 pmax 为空，由 `PARTITION_OVERFLOW` 保证） |
| **G22** | **列存表不支持 UNIQUE 索引**（`psort does not support unique indexes`）、不支持 FK、不支持 CHECK | §5.3 的物理护栏无法落地 → 改由 DQ 规则 `DWD_DUPLICATE_KEY`、`STAT_DATE_NOT_TRUNCATED` 承担 |
| **G23** | **分区表谓词区间完全超出最大边界时，查询报 `Fail to find partition from sequence.` 而非返回 0 行** | 所有分区表（含列存）**都必须保留 MAXVALUE 兜底分区**，否则 DQ/报表在合法"未来期间"上会崩 |
| **G24** | **A 模式 `::date` 不做日截断**：`date` 等价 Oracle DATE(= timestamp(0))，只做秒精度四舍五入。实测 `(timestamptz '2025-05-31 23:59:59.999999+00' AT TIME ZONE 'UTC')::date = 2025-06-01 00:00:00` | **两类静默错误**：① 全部行保留时分秒 → 下游 `GROUP BY stat_date` 变按秒分组（实测 17671/17673 行受影响）；② 月末最后一微秒被舍入进下月，直接造成月末收入错记。**一律用 `date_trunc('day', ...)`** |
| **G25** | **A 模式 `date - date` 返回 `interval`**（标准 PostgreSQL 返回 integer） | 直接参与算术报 `types integer and interval cannot be matched`。天数差用 `EXTRACT(EPOCH FROM ...)/86400` |
| **G26** | `gsql -c "多条语句"` **只输出最后一条结果** | 断言脚本必须用 `-f` 文件形式；`/` 包体终止符也只在 `-f` 下生效 |
| **G27** | `ADD PARTITION` **不接受 `UPDATE GLOBAL INDEX`** 子句（DROP/TRUNCATE/SPLIT 接受） | 分区 DDL 需按操作类型区分是否附加该子句 |
| **G28** | **`ALTER TABLE ... TRUNCATE/DROP PARTITION` 是 DDL，不受 `ROLLBACK` 保护** | 注入测试**绝不可对源表做分区 DDL**。实施期曾因此真实删除 payment 2022-01 的 723 行（已从 `data.sql` 恢复并逐月核对一致）。`GLOBAL_INDEX_INVALID` 注入改用 dw 下 scratch 表 |
| **G29** | **ID 水位线轨的前提是"所有写入方共用同一单调序列"**，该前提很容易被破坏 | 实测复现：造数夹具用 9e8 段显式 id → 水位线被推到 900099999 → 后续 id 较小的补录行**既不满足 ID 轨也不在 TS 回溯窗内 → 双轨全漏**。<br>**缓解（已落地）**：① 造数/迁移脚本结束时强制重置水位线（已加入 `t1-deterministic.sql`）；② **月度全量对账 `RECON_DWD_VS_BASE` 不可省** —— Q1.11-C2 已验证它能捕获该缺口并由整月重建闭合。<br>这也再次印证 §6.3 的结论：**增量方案原理上无法自证完整，全量对账是必需的兜底而非可选项** |

| **G30** | **`FILTER (WHERE ...)` 在列存表上报 `variable not found in subplan target list`**（行存表上可用） | 早前"FILTER 可用"的结论是在行存 `payment` 上验证的，**需按存储形态区分**。DWD/DWS 均为列存 → `PKG_DWS` 全部改用 `count(CASE WHEN ... THEN 1 END)` |
| **G31** | **快照表的不可变保护是绝对的**：误写/测试写入的行同样**永久无法删除** | 实施期手工验证触发器时写入的 `TEST` 行永久留存，导致后续 QA 的绝对值断言失效。**规约**：① 生产环境禁止向 `rpt_disclosure_snapshot` 做任何测试写入；② QA 一律用"基线 + 增量"断言；③ 非生产清理只能靠 DROP/重建表（属可审计事件） |
| **G32** | **A 模式裸 `SELECT ... INTO` 在无结果时报 `query returned no rows when process INTO`**，而非把变量置 NULL | 会导致后续的友好报错分支永远走不到。**规约**：可能无行的查询一律用聚合改写（`SELECT COALESCE(max(x), 默认值) INTO`）或先用 `count(*)` 判存在性。已修 `close_period` 与 `plan_increment` 两处 |
| **G33** | **指纹 md5 汇总必须 `ORDER BY 主键`** | 不排序则同一数据集在不同扫描顺序下产出不同 checksum，**整个指纹机制静默失效**（可重算性无从证明）|
### Phase 1 QA 实际执行范围（超出原 §9 计划）

原计划 Q1.1–Q1.10 之外，实施期新增两组：

| 编号 | 内容 | 脚本 |
|---|---|---|
| **Q1.6** | DQ 规则注入测试 INJ-1~INJ-5（重复键 / 未截断 stat_date / 源侧删除 / 兜底分区溢出 / 全局索引失效） | `sqls/dw/tests/qa-phase1-injection.sql` |
| **Q1.11** | 水位线双轨增量验收 A/B1/B2/C1/C2a/C2b/C2c/D。其中 **C2 刻意验证"设计上会漏、由对账兜住"** 的完整链路 | `sqls/dw/tests/qa-phase1-incremental.sql` |

> ⚠️ Q1.11-B1 的期望值需注意：由于 `lookback_days` 回溯窗口存在，**近月每次增量都会被重扫**，这是回补迟到数据的设计意图。断言应为"重建月份数 ≤ 回溯窗覆盖范围"，而非"无新数据时重建 0 个月"（后者与回溯窗设计自相矛盾）。

### §10.1-Q2 已降级为配置开关（不再阻塞 Phase 2）

原方案把 O1/O2/O3 列为"必须用户决策的架构选择"。实施中改为**双模式实现**，Q2 因此从架构选择降级为配置开关：

| 模式 | 实现 | 代价 |
|---|---|---|
| `DIRECT` | `PKG_ORCH` 直接调用 `build_*` 过程 | 受 G13 限制，重型聚合无 SMP |
| `QUEUE` | `PKG_ORCH` 把 `PKG_DWD.gen_*_sql()` 产出的**裸 DELETE+INSERT** 投递到 `etl_task_queue`，外部 worker 以顶层语句提交 | 多一个 worker 进程；SQL 文本两处定义 |

调用方式：`CALL dw.pkg_orch.run_monthly(date '2025-03-01', 'RUN_ID', 'QUEUE');`

**SQL 两处定义的漂移风险由强制断言守护**：`qa-phase2-orch.sql` 的 Q2.13/Q2.13b 对同一期间分别用 DIRECT 与 QUEUE 产出，双向 `EXCEPT` 必须为 0。改动任一处都必须重跑。

轻量步骤（分区哨兵、DIM 构建）恒为 DIRECT：它们是 DDL / 小表全量重建，非 SMP 受益对象，且 DWD 依赖 DIM 先完成。

**依赖链必须严格串行（seq 3→4→5）**：`etl_task_queue.depends_on` 只能指向单个 `seq_no`，若让 DQ 同时依赖 payment 与 rental 两步，就会出现"payment 失败但 rental 成功 → DQ 仍被放行"的错误放行。

### Phase 2 已交付部分

| 交付物 | 说明 |
|---|---|
| `sqls/dw/program/04-pkg-orch.sql` | `PKG_ORCH.run_daily/run_monthly`（双模式）+ `enqueue`（幂等） |
| `sqls/dw/program/02-pkg-dwd.sql` | 新增 `gen_payment_sql` / `gen_rental_sql`（QUEUE 模式的裸 SQL 源） |
| `sqls/dw/scripts/etl_worker.sh` | 外部 worker，完整实现契约 K1~K10 |
| `sqls/dw/tests/qa-phase2-orch.sql` | Q2.9~Q2.13b（裸 SQL 校验、串行链、入队幂等、参数校验、**双模式等价性**） |
| `sqls/dw/tests/qa-phase2-worker.sh` | W-1~W-4（依赖阻塞+退出码、重试成功、重试上界、僵死回收） |

**worker 实现期踩到的两个 bug（已修并写入注释）**：
1. dry-run 早期用"领取后回滚 attempt"实现 → 同一任务被反复领取 → **无限循环**。改为只读枚举、不领取。
2. `UPDATE ... RETURNING` 在 `-t -A` 下**仍输出命令标签 `UPDATE 1`**，污染字段解析（`step_name` 带上标签）。必须 `grep -E '^[0-9]+\|'` 过滤。

**worker 测试用例本身的两个陷阱（已修并写入注释）**：
1. `CASE WHEN cond THEN 1 ELSE 1/0 END` 两分支均为常量 → **常量折叠**使 `1/0` 在计划期即报错，与条件无关。
2. 用表计数实现"第 N 次成功"不可行：任务失败时整个事务回滚，**计数一起被回滚**。必须用**序列**（`nextval` 非事务性）。

### Phase 2 后半已交付（DWS + C1/C2/C3）

| 交付物 | 说明 |
|---|---|
| `sqls/dw/ddl/04-dws-tables.sql` | DWS 四表：日粒度三张（列存 + RANGE 月分区 + HIGH 压缩）+ `dws_sales_month_store`（行存 + **Ustore**，月表反复 UPDATE 场景） |
| `sqls/dw/program/05-pkg-dws.sql` | `PKG_DWS` 四个幂等构建过程 + `is_complete_period` 标记 |
| `sqls/dw/program/06-ads-views.sql` | C2：`v_ads_ops_sales_drill`（**GROUPING SETS + GROUPING() 四粒度下钻**）/ `staff_perf` / `rental_health`；C3：`v_ads_exec_month_trend`（**月份骨架 + LAG 环比/同比 + ROWS BETWEEN 移动平均**）/ `category_rank` |
| `sqls/dw/ddl/05-ads-tables.sql` + `program/07-pkg-ads.sql` | C1 大屏表（行存 + zstd + **HyperLogLog 近似 UV**）+ `PKG_ADS` 双模式刷新（REPLACE/SWAP） |
| `sqls/dw/tests/qa-phase2-dws-ads.sql` / `qa-phase2-c1-concurrent.sh` | Q2.1~Q2.8 + C1 并发读断言 |

QA 证据：DWS 三粒度与 DWD 金额逐项一致（17673 / 86391.36）；C3 不完整期环比/同比全 NULL、
缺月骨架无跳跃（Q2.4）、32 月跨度下 19 行有同比（Q2.5）；C2 总计行对账一致（Q2.6）；
C1 REPLACE 5.01ms vs SWAP 9.68ms（V5 结论见 §5.4）。

---

### 新增/修订的口径问题（已回写 `metric-definitions.md`，待业务方裁定）

| 编号 | 内容 |
|---|---|
| **B4** | 门店三态未覆盖「无 inventory 但有 customer」→ 实现落为第四态 `UNCLASSIFIED` + DQ 告警 |
| **B5** | **实测 964/1000 部影片属于多个品类**（2 类 561 部、3 类 403 部）。取 `min(category_id)` 单一归属会使单品类金额偏差。**品类维度披露报表在 B5 裁定前不得发布** |

### 新增 DQ 规则（超出原附录 A）

`STORE_UNCLASSIFIED`(WARN)、`DWD_DUPLICATE_KEY`(CRITICAL)、`STAT_DATE_NOT_TRUNCATED`(CRITICAL)、`FILM_MULTI_CATEGORY`(WARN)、`RECON_DWD_VS_BASE`(CRITICAL，替代原 `RECON_L2_VS_BASE` 命名)

### 规则修订

- `STORE_NO_STAFF` 改用 `pay_cnt_all_time`（不带报告期过滤）：结构性缺陷不能因"当期无交易"被漏报。实测 store_id=2 全时段 8121 笔交易、0 个 staff，若按报告期过滤会被漏报。
- `PERIOD_INCOMPLETE` 收窄为只检查**数据区间的首月与末月**。早期按"日历完整性"检查会误报 31/32 个月，噪声淹没真信号。

---

### Phase 3 已交付

| 交付物 | 说明 |
|---|---|
| `sqls/dw/ddl/06-rpt-tables.sql` | 披露层四件套 + 不可变触发器 + B1~B5 录入为 DRAFT |
| `sqls/dw/program/08-pkg-disclose.sql` | `take_fingerprint` / `verify_fingerprint` / `close_period` / `recompute_period` |
| `sqls/dw/tests/qa-phase3-disclose.sh` + `.sql` | Q3.1~Q3.7（10 项断言，shell 驱动保证幂等） |

**两道硬闸门（均无 force 后门）**：
1. 该期间存在 CRITICAL 级 DQ 结论 → `ORA-20042` 拒绝
2. 存在未 `APPROVED` 的口径定义 → `ORA-20043` 拒绝

**§10.1-Q5 已降级为配置**：B1~B5 全部录入 `dw.rpt_metric_def` 并置 `DRAFT`。业务方裁定后只需
`UPDATE rpt_metric_def SET status='APPROVED', approved_by=...`，无需改代码。
**但闸门 2 保证未签字前任何期间都无法冻结披露** —— 这是 RK1 的最后一道防线。

### 结构性 DQ 规则的全局语义（设计特性，非缺陷）

`DATE_RANGE_MISMATCH` / `STORE_NO_STAFF` / `MGR_ORPHAN` 等是**全局结构性**规则，不按期间过滤。
因此一条结构性 CRITICAL 会阻塞**所有**期间的冻结，直到源头被修复。这对披露是正确语义
（结构缺陷未修复时不应对外披露），但意味着 `close_period` 的成功路径必须先走整改步骤 ——
Q3 的 QA 因此完整演示 **"注入 → 拒绝 → 整改 → 冻结 → 重算"** 全流程。

---

### 跨版本佐证（5.0.0 实测，2026-08-27）

本机另发现 `opengauss/opengauss:5.0.0`（2023 年，无 KVecturbo，**可在 Apple Silicon 运行**）。
它同样是轻量版（无 SMP：dop=4 计划无 Streaming 算子；无 `dbe_scheduler`），
但提供了一个**第二个独立版本**来交叉验证关键平台约束：

| 项 | 5.0.0 | 7.0.1 lite | 结论 |
|---|---|---|---|
| 列存 `lag()` 等窗口函数 | ✅ 可用 | ✅ 可用 | **V7 跨版本一致**：文档"列存仅 rank/row_number"在两版均不成立 |
| 列存 `FILTER (WHERE ...)` | ❌ **语法级不支持** | ❌ 执行期报 subplan 错误 | **G30 加强**：5.0.0 直接语法错误，7.0.1 运行时错误——均不可用，规约"一律 `CASE WHEN`"跨版本成立 |
| 列存 INTERVAL 自动分区 | ❌ `cstore/timeseries don't support interval partition type` | ❌ 同错误 | **G34 跨版本一致**：显式 `ADD PARTITION` 哨兵是列存唯一路径 |
| `dbe_scheduler` / `dbe_task` | ❌ 无 | ❌ 无 | **V15 跨版本一致**：lite 系列均无，调度只能外部触发 + `PKG_SERVICE` |
| `enable_codegen` | on（存在） | off（存在） | 5.0.0 默认开启但无 SMP；Codegen 与 SMP 是不同能力 |

**意义**：这些结论从"7.0.1 单版本实测"升级为"5.0.0 + 7.0.1 双版本一致"，降低了版本特有假象
的风险。5.0.0 镜像 `og50` 探针容器已清理（临时表已删），主库未受影响。

**SMP 决定性计时实验（5.0.0，500 万行列存聚合，各 3 次取中位）**：
- dop=1 中位 ≈ 119.9ms（118.1 / 119.9 / 141.7）
- dop=4 中位 ≈ 116.3ms（114.4 / 119.9 / 116.3）
- **加速比 ≈ 1.03x → 确认无 SMP**。5.0.0 的 `enable_codegen=on` 是 LLVM 表达式 JIT，
  与多核并行无关；无 Streaming 算子的计划佐证与此一致。

**最终定性（G40）**：本机（Apple Silicon Docker）可运行的全部 openGauss 版本
（7.0.1 lite、5.0.0）经计划（无 Streaming/dop 算子）与计时（加速比 ~1.03x）双路确认
**均无 SMP**。`enable_codegen` 存在不代表 SMP 可用（Codegen=LLVM JIT，SMP=多核并行，
是两项独立能力）。含 SMP 的企业版/极简版必须 x86_64 或鲲鹏环境 —— 此结论由三个
版本/两次实验交叉确认，不是疏漏。

**补充验证（2026-08-27，第四个版本）**：另拉取 `opengauss/opengauss-server:7.0.0-RC3.B025`
（企业版镜像，arm64 原生，**可在 Apple Silicon 启动** —— KVecturbo CPU 检测在 RC3 不再
崩溃，与 RC2 不同）。实测其行为与轻量版一致：
- `dbe_scheduler`/`dbe_task` **不存在**（V15 进一步确认：企业版 Docker 镜像同样走
  `PKG_SERVICE` 调度，与 lite 无差异）
- `enable_smp` GUC 不存在；500 万行 dop=1 vs 4 加速比 ≈ **1.01x** → **无 SMP**
- `enable_codegen` 可开关但无多核并行（再次印证 Codegen ≠ SMP）

**结论（G41）**：`opengauss/opengauss-server` 的 Docker 镜像（RC2 与 RC3 均验证）实质为
**轻量版内核** —— 与 `opengauss/opengauss`（lite）功能等价，仅 RC3 修复了 KVecturbo 在
Apple Silicon 的崩溃。**"换企业版镜像 tag"无法获得 SMP**；含 SMP 的内核只能通过
x86_64/鲲鹏上的官方企业版**源码/二进制包**部署（非 Docker Hub 镜像）获取。这排除了
通过 Docker Hub 在企业版镜像上做 SMP 验证的最后路径。

**后续可探索路径（已确认但未投入，记录备查）**：官方下载页（opengauss.org）对 6.0.5 LTS 提供
**企业版 / 极简版 / 轻量版**三种 AArch64 二进制包；OBS 上已确认 `openGauss-Lite-6.0.5-*` 存在
（35.8MB）。文档矩阵称**极简版含 SMP/LLVM/向量化**（仅缺 CM/OM）。若需要在本机做 SMP 验证，
可尝试下载极简版二进制在容器内手动部署单节点实例（非 Docker 镜像，规避 G41 的"镜像=轻量版"
问题）。未投入原因：① 核心包 URL 由前端 JS 动态生成，curl 拿不到；② 手动部署工作量大且
不确定极简版是否同样带 KVecturbo；③ 更稳妥的路径仍是 x86_64/鲲鹏真机。

**已穷尽程序化路径（2026-08-27 最终确认）**：OBS 桶目录列举被拒（需鉴权）；极简版/企业版
核心包名在 6.0.5/7.0.0 下的多种命名（Enterprise/Minimal/all/裸名）均 HTTP 403 未命中；
安装文档页为 JS 渲染无法抓取包名。**结论：极简版二进制只能从官网下载页人工获取，或需
x86_64/鲲鹏真机** —— SMP 验证在本机不存在程序化获取路径。

**逆向下载页数据源（2026-08-27 最终）**：官网下载页为 VitePress SPA，核心包下载链接
由运行时后端 API 提供，不在静态 JS 中（`app.js`/`zh_download_index.md.lean.js`/
`TheDownload`/`DownloadContent`/`index` 组件均无核心包 URL；仅驱动包静态可抓）。
已确认 `openGauss-Lite-6.0.5-*` OBS 直链可用，但极简版/企业版包需页面点击触发 API。
**结论升级**：即使逆向出 API，在 Apple Silicon 手动部署非容器化单节点 openGauss 属
小时级工作且极简版可能同样带 KVecturbo（G37）。**SMP 验证在本机的成本已远超其价值，
维持"需 x86_64/鲲鹏真机或官网人工下载"结论，不再投入**。

---

### 企业版验证套件已交付（Q1 剩余项的"一条命令"化）

**环境就绪后，剩余 V 项的裁定只需一条命令**：

```bash
CONTAINER=<企业版容器> bash sqls/dw/tests/qa-enterprise.sh
```

| 交付物 | 内容 |
|---|---|
| `sqls/dw/tests/qa-enterprise.sql` | 计时（`query_dop=1 vs 4` 各 3 次、过程内 `EXECUTE IMMEDIATE` 3 次）+ V15（`dbe_scheduler`/`dbe_task` 存在性）+ Codegen GUC 探测 |
| `sqls/dw/tests/qa-enterprise.sh` | 捕获 EXPLAIN 输出并 grep `Streaming`/`dop` 算子，汇总 V1 裁定 |

**V1 裁定逻辑**（§5.3 O1/O3 的唯一依据）：
- 顶层有并行 + 过程内无 → **维持 O1**（队列模式，外部 worker 顶层提交）
- 顶层有并行 + 过程内也有 → **简化为 O3**（纯库内，移除外部 worker）
- 顶层无并行 → 环境无 SMP（lite），不可判定，需换环境

**套件已在 lite 上验证安全降级**：零 ERROR，E-0 正确识别 lite，V15/SMP-1/V1 全部输出明确
SKIP/"不可判定"而非误报（V2 已实测 lite 接受 `query_dop` 但不产生并行算子，故不可误判为 PASS）。

**套件自检抓出的 4 个缺陷（均已修复，均为假结论隐患）**：
1. SQL 头部注释误用 `#`（shell 风格）→ 语法错误。
2. `EXPLAIN (COSTS OFF) CALL proc()` **语法非法**，且驱动 `2>/dev/null` 把报错吞成假
   "V1-RESULT=0"。→ V1 改用计时比判定（G38 延伸：过程内计划无法用 EXPLAIN 捕获）。
3. **计时在亚 20ms 被噪声主导**：lite 上同查询 0.158ms~11.5ms 抖动，曾把纯噪声误判为
   "1.35x SMP 提速"。→ 强制 base 中位 > 100ms（可调 `MIN_BASE_MS`）才采信，否则
   INCONCLUSIVE。实测 300 万行多键聚合仅 81ms，故指引需 1000 万+ 行。
4. **探针查询不一致**：过程内跑简单 `count/sum` 而顶层跑多键聚合，产生假"4 倍提速"。
   → `qa_v1_exec` 与 TIMING 段统一为同一重 SQL。

**结论（G39）**：openGauss 上"过程内查询是否获得并行"**只能由计时比判定，无法由计划
捕获判定**（EXPLAIN 不能包 CALL、不能作子查询）。且计时判定强依赖数据规模——
数据不足时如实报告 INCONCLUSIVE 比给出假裁定更重要。

**实施期实测约束（G38）**：openGauss **不支持 `EXPLAIN` 作子查询 / `CREATE TABLE AS` / `FOR ... IN (EXPLAIN ...)` 数据源**（均报语法错误，仅可直接执行输出文本）。因此计划捕获必须放在 shell 层对 EXPLAIN 文本 grep，不能放 SQL 内。

---

### Phase 4 已交付（lite 串行基线）

| 交付物 | 说明 |
|---|---|
| `sqls/dw/tests/fixtures/t3-scale.sh` + `.sql` | 参数化规模造数（默认 20 万 rental / 100 万 payment / 12 月，可扩到亿级） |
| `sqls/dw/docs/phase4-baseline.md` | 串行基线数据 + V2~V13 实测结论 + 对官方文档的 3 处修正 |

**串行基线（payment 101.8 万行）**：DIM 3.50s ｜ DWD payment 8.53s ｜ DWD rental 1.08s ｜
DWS 2.52s ｜ DQ 2.15s ｜ C1 32ms ｜**端到端 ≈ 17.8s**。
DWD 单行成本 ≈ 8.4 μs → 1 亿行全量重建外推 ≈ 20 分钟，**仍在 §11 的 30 分钟阈值内**
（且生产走增量，实际远低于此）。

**本轮解决的 V 项**：V2（lite 确认无 SMP）、V3（lite 列存确认走向量化）、V4（列存不支持
INTERVAL 自动分区 → 确认 DD5 哨兵是唯一路径）、V7（列存支持全部 10 种窗口函数 + frame，
推翻文档）、V8（GTT 可用）、V10（多列统计可用）、V11（Oracle 兼容语法全可用）、
V12（gs_dump/gs_probackup 可用，`gs_basebackup` lite 中不存在）、
V13（`ANALYZE ... PARTITION` 语法接受但不生效 → 只对整表 ANALYZE）。

**仍需企业版的**：V1（过程内 `EXECUTE IMMEDIATE` 是否受 G13 限制 → 决定 O1/O3）、
V14（企业版镜像可启动性，本机 7.7GB < 要求 12GB）、V15（DBE_SCHEDULER）、SMP/Codegen 加速幅度。

### G34~G36（Phase 4 新增）

| 编号 | 约束 | 影响 |
|---|---|---|
| **G34** | **列存表不支持 INTERVAL 自动分区**（`cstore/timeseries don't support interval partition type`） | 行存可用。确认 DD5 的显式 `ADD PARTITION` 哨兵对 dw 列存事实表是**唯一可行路径** |
| **G35** | **`ANALYZE ... PARTITION(名)` 语法被接受但不收集分区级统计**（实测前后 `pg_stats` 条目数不变） | 规约：只对整表 `ANALYZE`。方案原先标注的"需实测"至此闭环 |
| **G36** | **`gs_dump` 用位置参数指定库名，不支持 `-d`**；`gs_basebackup` 在 lite 中不存在 | C4 披露期物理备份只能用 `gs_probackup`；逻辑备份用 `gs_dump -n dw -s -f out.sql <dbname>` |

---

### T2 / SDV 已交付（R6 落地）

| 交付物 | 说明 |
|---|---|
| `sqls/dw/scripts/sdv_gen.py` | SDV 1.38.1，单表 `GaussianCopulaSynthesizer` + `Inequality` 约束 |
| `sqls/dw/tests/qa-t2-sdv.sh` + `qa-t2-sdv.sql` | 全链路驱动（导出种子 → 建模采样 → CSV → COPY → 6 项断言） |

**实测结果（20000 行采样，种子 payment 16049 / rental 16044）**：

| 断言 | 结果 |
|---|---|
| T2-1 入库行数 | 20000 ✅ |
| T2-2 `Inequality(rental_date < return_date)` 库内成立 | **0 违反** ✅ |
| T2-3 金额落在真实档位 | **100%** ✅ |
| T2-4 分布保真 | 中位数完全一致（3.99），均值偏差 **0.94% < 5%** ✅ |
| T2-5 时间范围 ⊆ 种子范围 | ✅（证实社区版无法外推跨度） |
| T2-6 未污染业务表与 T1 基线 | ✅ |

**实施期发现的一个 SDV 默认配置缺陷（已修）**：`amount` 若交给 SDV 自动识别为
`numerical`，GaussianCopula 按连续边缘分布拟合，而 Pagila 金额是**离散价格档位**
（仅 19 个取值）。实测后果：产出 **1026** 个不同取值、仅 **8.48%** 落在真实档位、
中位数从 3.99 偏到 **1.79**（低 55%）。修正为显式 `sdtype='categorical'` 后：
取值数 18、命中率 100%、中位数与均值均吻合。**规约：离散数值列必须显式声明为
categorical，不可依赖自动识别。**

**T2 的能力边界（与方案 §8.1 判断一致，已实测确认）**：
1. 合成日期被 `enforce_min_max_values=True` 锁在种子范围内 → **无法产出跨多年数据**，
   故同比验证与规模压测必须靠 T1/T3 的 SQL 侧造数。
2. 产出值不可预知 → **不能替代 T1 做正确性断言**，只用于回归测试的分布真实感。
3. 单表建模 + 外键由 SQL 侧补齐 → 未使用 `HMASynthesizer`（官方明示公开版
   "not meant for scale" 且限约 5 表/1 层深度，Pagila 是 15 表多层）。
4. 许可证 **BUSL-1.1**（非 MIT）：Additional Use Grant 允许生产使用，仅禁止将 SDV
   作为"合成数据服务"对外商业提供。内部测试造数在授权范围内，建议法务复核一次。

**环境要求**：Python 3.9+ 与独立 venv（`pip install sdv` 会拉入 torch 等重依赖，
本机实测 90 个包）。因此 SDV 是**离线造数工具链**的一部分，不进数据库运行时依赖。

---

## 11. 容量升级阈值（达到才做，避免过度设计）

| 动作 | 触发阈值 |
|---|---|
| 补独立 ODS 层 | 数仓需与业务库物理隔离时 |
| DWS 二级分区 | 单 DWS 表 > 5 亿行**且**已确认不需 MERGE/UPSERT（G15） |
| C1 引入影子表切换 | V5 实测重建 > 200ms |
| 引入企业版 SMP | 单次 ETL 串行 > 30 分钟 |
| 列存 delta 表 `enable_delta_store` | 出现小批量高频写入列存表的场景 |
| 分表/归档 | DWD 单表 > 20 亿行或需按年归档 |

---

## 12. 风险登记

| 编号 | 风险 | 等级 | 缓解 |
|---|---|---|---|
| RK1 | **D1 门店数口径污染 C4 披露**（"500 家门店"进入公开文件 = 实质性错误陈述） | **极高** | DIM 层 `store_status` 三态 + 禁止任何层直接 `FROM store` + Q5 业务签字 + CRITICAL 硬闸门 |
| RK2 | G13 使重型聚合无法并行 | 高 | Q2 决策 + V1 验证 |
| RK3 | 汇总表金额列误用 `numeric(5,2)` 导致溢出 | 高 | 汇总列一律 `numeric(18,2)`；G4 表明风险在 DDL 而非聚合；DQ 规则 `AMOUNT_OVERFLOW` |
| RK4 | 分区键被函数包裹致裁剪失效 | 高 | 强制半开区间签名（§5.2）+ `EXPLAIN` 断言纳入验收 |
| RK5 | A 模式空串≡NULL 导致 `COUNT` 口径漂移 | 中高 | 口径文档明确每个指标用 `COUNT(*)` 还是 `COUNT(col)`；L1 层空串映射 `'(未填写)'` |
| RK6 | 企业版环境不可得（G12） | 中 | Phase 0-3 全部在 lite 验证功能；Phase 4 再解决环境 |
| RK7 | SDV 产出无法断言，误当正确性验证 | 中 | DD11 三层分工写入方案；T1 才是正确性来源 |
| RK8 | GLOBAL 索引因 ALTER 未加 `UPDATE GLOBAL INDEX` 失效（G18） | 中 | 分区哨兵过程统一附加该子句；DQ 规则检查索引有效性 |
| RK9 | 过度设计（4 层 + 列存 + 真增量）在实际规模未达时成为负担 | 中 | §11 阈值表；Phase 分期；功能优先 |
| RK10 | 官方文档自相矛盾导致选型错误 | 中 | §10 V 项全部实测；不以文档默认值为准 |

---

## 附录 A — DQ 规则集（初版）

| rule_code | severity | 检查内容 | 对应缺陷 |
|---|---|---|---|
| `STORE_NO_DATA` | WARN | 门店无 inventory 且无 customer | D1 |
| `STORE_NO_STAFF` | **CRITICAL** | 有业务但无 staff | D3 |
| `MGR_ORPHAN` | **CRITICAL** | `store.manager_staff_id` 悬空 | D5 |
| `DATE_RANGE_MISMATCH` | **CRITICAL** | `max(rental_date) > max(payment_date)` | D4 |
| `PERIOD_INCOMPLETE` | WARN | 期间首/末不完整 | D6 |
| `PARTITION_OVERFLOW` | **CRITICAL** | MAXVALUE 兜底分区行数 > 0 | S2 |
| `AMOUNT_OVERFLOW` | **CRITICAL** | 汇总列接近类型上限 | S5/G4 |
| `RECON_L2_VS_BASE` | **CRITICAL** | DWS 汇总 vs 源表直算不一致 | §6.3 |
| `SRC_ROW_DELETED` | WARN | 源侧物理删除检出 | S4 |
| `WATERMARK_STALL` | **CRITICAL** | 水位线长时间未推进 | §6.2 |
| `YOY_BASE_MISSING` | WARN | YoY 基线缺失（历史不足） | G8 |
| `GLOBAL_INDEX_INVALID` | **CRITICAL** | GLOBAL 索引失效 | G18 |
| `FINGERPRINT_MISMATCH` | **CRITICAL** | 期间输入指纹与已冻结指纹不一致（源数据被改动） | DD8 / §Q3.4 |
| `DWD_DUPLICATE_KEY` | **CRITICAL** | DWD 明细重复（列存不支持 UNIQUE 索引的替代检测） | G22 |
| `FILM_MULTI_CATEGORY` | WARN | 多品类影片影响面（B5 待裁定） | §5 |
| `RECON_DWD_VS_BASE` | **CRITICAL** | DWD 与源表逐月笔数/金额对账（实施期由 RECON_L2_VS_BASE 更名） | §6.3 |
| `STAT_DATE_NOT_TRUNCATED` | **CRITICAL** | stat_date 非整日零点（`::date` 不做日截断的兜底检测） | G24 |
| `STORE_UNCLASSIFIED` | WARN | 门店四态中的 UNCLASSIFIED（无库存但有客户，B4 待裁定） | §1.1 |

**闸门语义（关键的不对称设计）**：
- **C1/C2/C3**：CRITICAL 不阻塞，但 DWS 行打 `dq_flag`，ADS 视图必须透出 → "带瑕疵可用"。
- **C4 披露**：**0 CRITICAL 才允许 `close_period`**，硬闸门、代码级拒绝、不留 `p_force` 后门（若保留必须记录审批人并在快照上永久标记）。

---

## 附录 B — 关键参考

**openGauss 官方文档**
- [版本能力矩阵（latest）](https://docs.opengauss.org/zh/docs/latest/about_opengauss/version_capability.html)
- [增量物化视图](https://docs.opengauss.org/zh/docs/latest/sql_reference/incremental_materialized_view.html)
- [配置并行查询功能（SMP 限制）](https://docs.opengauss.org/zh/docs/latest/performance_tuning_guide/configuring_the_parallel_query_function.html)
- [CREATE TABLE（列存选项）](https://docs.opengauss.org/zh/docs/latest/sql_reference/create_table.html)
- [CREATE TABLE PARTITION](https://docs.opengauss.org/zh/docs/latest/sql_reference/create_table_partition.html)
- [CREATE TABLE SUBPARTITION](https://docs.opengauss.org/zh/docs/latest/sql_reference/create_table_subpartition.html)
- [CREATE INDEX（LOCAL/GLOBAL）](https://docs.opengauss.org/zh/docs/latest/sql_reference/create_index.html)
- [MERGE INTO](https://docs.opengauss.org/zh/docs/latest/sql_reference/merge_into.html)
- [全局临时表](https://docs.opengauss.org/zh/docs/latest/characteristic_description/global_temporary_table.html)
- [SQL PATCH](https://docs.opengauss.org/zh/docs/latest/characteristic_description/sql_patch.html)
- [Plan Hint 调优概述](https://docs.opengauss.org/zh/docs/7.0.0-RC2/docs/PerformanceTuningGuide/Plan-Hint调优概述.html)
- [更新统计信息（多列统计）](https://docs.opengauss.org/zh/docs/latest/performance_tuning_guide/update_statistics.html)
- [OLTP 场景数据压缩（行存压缩）](https://docs.opengauss.org/zh/docs/latest/database_administration_guide/data_compression_in_oltp_scenarios.html)
- [定时任务（job_queue_processes）](https://docs.opengauss.org/zh/docs/latest/database_reference/scheduled_task.html)
- [PKG_SERVICE](https://docs.opengauss.org/zh/docs/5.0.0/docs/SQLReference/PKG_SERVICE.html)
- [7.0.0-RC1-lite 列存储教程](https://docs.opengauss.org/zh/docs/7.0.0-RC1-lite/docs/BriefTutorial/列存储.html)

**SDV**
- [官方文档](https://docs.sdv.dev/sdv/welcome-to-the-sdv.md) · [HMASynthesizer 限制](https://docs.sdv.dev/sdv/modeling/multi-table-synthesizers/hmasynthesizer) · [Compare Features（社区 vs Enterprise）](https://docs.sdv.dev/sdv/explore/sdv-enterprise/compare-features.md) · [LICENSE (BUSL-1.1)](https://github.com/sdv-dev/SDV/blob/main/LICENSE) · [Issue #2110（官方"not meant for scale"表态）](https://github.com/sdv-dev/SDV/issues/2110)

**本仓库**
- `sqls/ddl/schema.sql` · `sqls/program/{functions,triggers,views}.sql` · `benchmark/v1/` · `benchmark/v3/`（窗口函数/GROUPING SETS 已验证物料）
