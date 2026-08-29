# PROJECT KNOWLEDGE BASE

**Generated:** 2026-08-27
**Branch:** main

## OVERVIEW

Pagila — Sakila 示例数据库的 openGauss 移植版。从 PostgreSQL 迁移到 openGauss 7.0（Oracle 兼容模式）。Docker Compose 自动初始化 schema + 数据。核心是 schema/data/Docker 项目，附带一套 openGauss EXPLAIN 评估套件（`benchmark/`：SQL 查询集 + EXPLAIN 物料 + ground-truth case + 工具脚本）用于评估 EXPLAIN 诊断工具，以及一套**分层报表体系**（`sqls/dw/`：DIM/DWD/DWS/ADS 四层 + 披露层 + 13 套 QA 验收套件）。

## STRUCTURE

```
ogagila/
├── docker-compose.yml              # openGauss + pgAdmin4 编排（含 16 个 9-dw-* 初始化文件）
├── docker/
│   └── gsql-wrapper.sh             # gsql 包装脚本（自动注入 gaussdb 用户名密码）
├── sqls/
│   ├── ddl/                        # DDL：表、序列、类型、约束、索引
│   │   ├── init-gaussdb-schema.sql # 创建 gaussdb schema（防 JDBC 驱动 $user search_path 报错）
│   │   ├── schema.sql              # 主 schema：15 表 + payment 分区表（7 内联分区）
│   │   └── schema-jsonb.sql        # JSONB 扩展：packages_apt/yum_postgresql_org
│   ├── program/                    # 存储程序：函数、触发器、视图
│   │   ├── functions.sql           # 10 函数 + 1 自定义聚合 group_concat
│   │   ├── triggers.sql            # 15 触发器（14 last_update + 1 fulltext）
│   │   └── views.sql               # 7 视图 + 1 物化视图
│   ├── dw/                         # 分层报表体系（数仓：DIM/DWD/DWS/ADS + 披露层）
│   │   ├── ddl/                    # 7 个文件：源修复、基础设施、DIM、DWD、DWS、ADS、披露四件套
│   │   ├── program/                # 9 个 PACKAGE + 视图集：ETL_CORE/DIM/DWD/DQ/ORCH/DWS/ADS/DISCLOSE
│   │   ├── scripts/                # etl_worker.sh（K1~K10 契约）、sdv_gen.py（SDV 造数）
│   │   ├── docs/                   # metric-definitions.md（口径基线）、phase4-baseline.md（性能基线）
│   │   └── tests/                  # 13 套 QA：qa-phase0~3、qa-t2-sdv、qa-enterprise、fixtures(t1/t3)
│   └── init_data/                  # 初始数据
│       ├── data.sql                # 业务数据（COPY 格式，payment 重定向到父表）
│       ├── data-apt-jsonb.sql      # apt 包 JSONB 数据（纯 SQL，67109 行）
│       └── data-yum-jsonb.sql      # yum 包 JSONB 数据（纯 SQL，84685 行）
├── benchmark/                      # EXPLAIN 评估套件：SQL + EXPLAIN 物料 + ground-truth case + 工具
│   ├── README.md                   # 唯一总文档（合并版）
│   ├── scripts/                    # Python 工具
│   │   ├── run_explain.py          # Stage A：跑 EXPLAIN ANALYZE，支持 --version 切换
│   │   └── build_cases.py          # Stage B：合成 ground-truth case，支持 --version 切换
│   ├── groundtruth.schema.json     # case JSON Schema (Draft 2020-12)
│   └── v1/                         # 版本化（可扩展 v2/v3...）
│       ├── queries.sql             # 97 条 query（含 -- @id/@target/@severity/@scenario 标记）
│       ├── queries.md              # 该版本人类可读说明
│       ├── queries_meta.json       # 机器可读元数据（target_rule / severity / scenario）
│       ├── explains/               # Stage A 产物：Q*.explain + Q*.meta.json + index.json
│       ├── cases/                  # Stage B 产物：OGEXP-GT-2026-0001.json ~ 0097.json
│       ├── case_index.json         # 97 case 索引（evaluator 可直接消费）
│       └── trigger_coverage.md     # 按规则维度的触发率报告
├── pagila-schema-diagram.png       # ER 图参考
├── pgadmin/                        # pgAdmin4 预配置
│   ├── pgadmin_servers.json        # 服务器定义 → 容器 pagila，用户 gaussdb
│   └── pgadmin_pass                # 密码文件（libpq .pgpass 格式）
├── .sisyphus/plans/                # 实施计划（opengauss-tiered-reporting.md）
├── README.md
└── LICENSE.txt
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| 理解表结构 | `sqls/ddl/schema.sql` | 15 表 + payment 分区表（7 内联分区） |
| JSONB 表 | `sqls/ddl/schema-jsonb.sql` | 2 表，用 SEQUENCE+nextval 替代 IDENTITY |
| 函数/聚合 | `sqls/program/functions.sql` | 含 `check_function_bodies = false` 头部（允许前向引用） |
| 触发器 | `sqls/program/triggers.sql` | 依赖 ddl/schema.sql 的表 + functions.sql 的触发器函数 |
| 视图 | `sqls/program/views.sql` | 含物化视图 MV 上的唯一索引 |
| 修改 Docker | `docker-compose.yml` | `GS_DB=pagila` 自动建库，25 个 SQL 文件按序号自动加载（9 基础 + 16 个 9-dw-*） |
| 初始化顺序 | `docker-compose.yml` volumes | 0-gaussdb-schema → 1-ddl → 2-ddl-jsonb → 3-functions → 4-triggers → 5-views → 6-data → 7-apt → 8-yum → 9-dw-*（DDL 00~06 → program 10~18） |
| pgAdmin 连接 | `pgadmin/pgadmin_servers.json` | Host=pagila, User=gaussdb, DB=pagila |
| 分区定义 | `sqls/ddl/schema.sql` payment 表 | openGauss 内联 `VALUES LESS THAN` 语法 |
| 报表分层总览 | `.sisyphus/plans/opengauss-tiered-reporting.md` | 1096 行方案：24 条实测约束（G18~G41）+ 13 套 QA 记录 |
| 数仓 DDL | `sqls/dw/ddl/` | 7 文件：00-source-fixes（MAXVALUE 兜底分区+F2 索引）/ 01-infra / 02-dim / 03-dwd / 04-dws / 05-ads / 06-rpt |
| 数仓存储程序 | `sqls/dw/program/` | 9 文件：00-pkg-etl-core（分区哨兵/水位线）/ 01-pkg-dim / 02-pkg-dwd / 03-pkg-dq / 04-pkg-orch / 05-pkg-dws / 06-ads-views / 07-pkg-ads / 08-pkg-disclose |
| 口径基线（B1~B5 待签字） | `sqls/dw/docs/metric-definitions.md` | 门店三态/统一截止日/COUNT 口径/品类归属（B5）/YoY 规则 |
| 性能基线 | `sqls/dw/docs/phase4-baseline.md` | lite 串行基线 + V2~V13 实测结论 |
| 造数三层 | `sqls/dw/tests/fixtures/` | T1 确定性（t1-deterministic.sql）/ T2 SDV（scripts/sdv_gen.py）/ T3 规模（t3-scale.sh） |
| QA 套件 | `sqls/dw/tests/` | 13 套：qa-phase0~3 + qa-t2-sdv + qa-enterprise + cv-assertions |
| ETL worker | `sqls/dw/scripts/etl_worker.sh` | 外部触发、库内编排（K1~K10 契约）；`PKG_ORCH` 双模式 DIRECT/QUEUE |
| EXPLAIN 测试 query | `benchmark/v1/queries.sql` | 97 条 query，每条用 `-- @id`/`-- @target`/`-- @severity`/`-- @scenario` 标记 |
| EXPLAIN 输出 | `benchmark/v1/explains/Q*.explain` | 真 EXPLAIN ANALYZE 输出 + `.meta.json`（含 warnings） |
| query 元数据 | `benchmark/v1/queries_meta.json` | target_rule / severity / scenario / is_healthy 标签 |
| 跑 EXPLAIN | `benchmark/scripts/run_explain.py` | 默认 v1，`--version v2` 切换版本，每条 query 在独立 BEGIN/ROLLBACK 内 |
| ground-truth case | `benchmark/v1/cases/OGEXP-GT-*.json` | 97 case，遵循 `benchmark/groundtruth.schema.json` |
| case 生成器 | `benchmark/scripts/build_cases.py` | 默认 v1，`--version v2` 联动读写 `benchmark/v2/` |
| case JSON Schema | `benchmark/groundtruth.schema.json` | Draft 2020-12，定义 case_id/source/input/ground_truth 结构 |
| 触发率报告 | `benchmark/v1/trigger_coverage.md` | 按规则维度统计 designed vs actually_triggered |

## CONVENTIONS

- **Oracle 兼容模式**：`datcompatibility = A`，空字符串等价于 NULL
- **OWNER 统一 `gaussdb`**：所有对象 owner 为 gaussdb（非 postgres）
- **序列模式**：`DEFAULT nextval('public.seq_name'::regclass)`（非 SERIAL/IDENTITY）
- **payment 分区**：内联 `PARTITION ... VALUES LESS THAN (...)`（非 PG 的 ATTACH 语法）
- **分区索引/FK 建在父表**：openGauss 内联分区不暴露为独立可查表
- **`last_update` 列**：触发器自动更新 — 不要手动设置
- **全文检索**：`film.fulltext`（tsvector 列）+ `tsvector_update_trigger` 内置触发器
- **Docker init 排序**：文件名数字前缀（`1-`, `2-`, `3-`）控制执行顺序
- **`ON_ERROR_STOP=1`**：Docker 初始化严格模式，任何 SQL 错误都会终止启动
- **加载顺序**：DDL → PROGRAM（functions → triggers → views）→ init_data → 9-dw-*（DDL → program）
- **数仓对象全限定命名**：`dw.` schema 前缀必写 —— 连接用户 `gaussdb` 的 `search_path` 为 `"$user", public`，裸名会解析到 `public` 或报错
- **数仓对象独立 schema `dw`**：不污染 `public` 的 Pagila 源对象
- **幂等规则**：每个 `build_*` 过程先 `DELETE 区间` 再 `INSERT`，单事务，过程内禁止 COMMIT
- **半开区间参数**：所有日期参数 `[from, to)`，闭区间会破坏分区裁剪与边界归属
- **日期截断用 `date_trunc('day', ...)` 而非 `::date`**：A 兼容模式下 `::date` 只做秒级四舍五入不做日截断（G24）
- **列存条件计数用 `count(CASE WHEN ... THEN 1 END)`**：`FILTER (WHERE)` 在列存表上不可用（G30）
- **列存表不支持**：UNIQUE 索引、FK、CHECK、INTERVAL 自动分区、`SPLIT PARTITION`（G21/G22/G34）
- **分区表必须保留 MAXVALUE 兜底分区**：无兜底时超界查询报 `Fail to find partition from sequence.`（G23）
- **结构性 DQ 规则全局生效**：一条结构性 CRITICAL（如 `STORE_NO_STAFF`）会阻塞所有期间冻结，直到源头修复

## ANTI-PATTERNS (THIS PROJECT)

- **不要使用 `CREATE DOMAIN`** — openGauss 不支持，已用 `integer` + 内联 CHECK 替代
- **不要使用 `GENERATED ALWAYS AS IDENTITY`** — Oracle 兼容模式不支持，用 SEQUENCE + nextval
- **不要使用 `operator(schema.||)` 语法** — openGauss 不支持，用普通 `||`
- **不要使用 PG 分区 ATTACH 语法** — 用 openGauss 内联 `VALUES LESS THAN`
- **不要在 text NOT NULL 列存空字符串** — Oracle 模式下空串= NULL，phone/district 已改为可空
- **不要用 `psql`/`pg_restore`** — 用 `gsql`/`gs_dump`/`gs_restore`
- **不要加载二进制 `.backup` 文件** — JSONB 数据已转为纯 SQL 文本格式
- **不要修改加载顺序** — functions.sql 必须在 triggers.sql 和 views.sql 之前加载（依赖关系）
- **开发凭据硬编码** — `GS_PASSWORD: Enmo@123`，pgAdmin: `admin@admin.com` / `root`。不要用于生产。
- **不要用 `::date` 做日截断** — A 兼容模式只做秒级四舍五入，月末 23:59:59.999 会被舍入进下月（G24）
- **不要在列存表用 `FILTER (WHERE ...)`** — 报 `variable not found in subplan target list` 或语法错误（G30）
- **不要对源表做分区 DDL 测试** — `TRUNCATE/DROP PARTITION` 是 DDL 不受 ROLLBACK 保护（G28，曾真实删除 payment 723 行）
- **不要用 `EXPLAIN` 作子查询/CTAS/包 CALL** — openGauss 仅支持独立语句输出文本（G38/G39）
- **不要在 `rpt_disclosure_snapshot` 写测试数据** — 不可变触发器使其永久无法删除（G31）
- **不要对不完整期间算环比/同比** — 必须 `is_complete_period` 且返回 NULL（实测 +228.46% 假暴增）
- **严禁 `COALESCE(prev_year, 0)` 填同比** — 会产出 ±∞% 增长率
- **造数/迁移后必须重置水位线** — 高位显式 id 会把 ID 轨永久抬高导致静默丢数（G29）

## COMMANDS

```bash
# 启动（空容器自动初始化全部 schema + 数据）
docker-compose up -d

# 连接数据库（推荐）
docker exec -it pagila gsql-pagila

# 执行单条 SQL
docker exec pagila gsql-pagila -c "SELECT count(*) FROM film;"

# pgAdmin Web UI
# http://localhost:5050  (admin@admin.com / root)

# 手动加载（非 Docker 场景）
gsql -d postgres -c "CREATE DATABASE pagila;"
gsql -d pagila -f sqls/ddl/schema.sql
gsql -d pagila -f sqls/ddl/schema-jsonb.sql
gsql -d pagila -f sqls/program/functions.sql
gsql -d pagila -f sqls/program/triggers.sql
gsql -d pagila -f sqls/program/views.sql
gsql -d pagila -f sqls/init_data/data.sql
gsql -d pagila -f sqls/init_data/data-apt-jsonb.sql
gsql -d pagila -f sqls/init_data/data-yum-jsonb.sql

# === EXPLAIN ground-truth 物料 ===
# 跑 EXPLAIN ANALYZE（需先启动 ogagila 容器）
pip install psycopg2-binary
python3 benchmark/scripts/run_explain.py --host localhost --port 5432 \
    --db pagila --user gaussdb --password Enmo@123
# 切换版本:--version v2

# 生成 ground-truth case JSON
python3 benchmark/scripts/build_cases.py
# 切换版本:--version v2（自动读写 benchmark/v2/，与 v1 完全隔离）

# === 数仓 QA（需先启动容器，DW 对象在 init 时自动创建）===
docker exec pagila gsql-pagila -f /dw-tests/qa-phase0.sql
docker exec pagila gsql-pagila -f /dw-tests/qa-phase1.sql
bash sqls/dw/tests/qa-phase2-worker.sh
bash sqls/dw/tests/qa-phase3-disclose.sh      # 披露层（重载夹具+重建各层，幂等）
bash sqls/dw/tests/qa-t2-sdv.sh --rows 20000  # SDV 造数（需 venv: python3 -m venv /tmp/sdvenv && pip install sdv）

# === 数仓造数三层 ===
docker exec pagila gsql-pagila -f /dw-tests/fixtures/t1-deterministic.sql   # T1 确定性夹具（CV1~CV14）
bash sqls/dw/tests/fixtures/t3-scale.sh --rentals 200000 --payments 1000000 --months 12  # T3 规模
docker exec pagila gsql-pagila -f /dw-tests/fixtures/t1-cleanup.sql         # 清理 T1

# === 企业版验证套件（需 x86_64/鲲鹏，本机 Apple Silicon 无 SMP）===
CONTAINER=<企业版容器> bash sqls/dw/tests/qa-enterprise.sh

# 停止（保留数据卷）
docker-compose down

# 完全清除（重新初始化）
docker-compose down -v
```

## NOTES

- 仓库名 `ogagila` ≠ 内容 `pagila` — 本地文件夹名，上游为 `devrimgunduz/pagila`
- openGauss 版本：7.0.0-RC1（lite build），Oracle 兼容模式 (`datcompatibility = A`)
- `sqls/program/functions.sql` 需 `SET check_function_bodies = false` 头部 — 函数间有前向引用
- `sqls/program/views.sql` 包含物化视图上的唯一索引 — 索引必须在 MV 创建后才能建立
- `pagila-schema-diagram.png` 是静态 ER 参考图 — 非代码生成
- pgAdmin 密码文件格式：`host:port:db:user:password`（libpq `.pgpass` 格式）
- JSONB 数据文件较大（~49MB + ~54MB）— 纯 SQL 文本，无 Git LFS
- Docker 初始化总耗时约 6 秒（不含镜像下载和 initdb）
- `gsql-pagila` 包装脚本自动注入 gaussdb 用户名密码 — openGauss 安全插件要求非 omm 用户必须密码认证
- `init-gaussdb-schema.sql` 创建 gaussdb schema — PostgreSQL JDBC 驱动默认 `SET search_path TO "$user", public`，无此 schema 会报 `ERROR: schema "gaussdb" does not exist`
- **queries + benchmark 多版本机制**：`benchmark/` 整合了 SQL 查询集、EXPLAIN 物料、ground-truth case 和工具脚本。`scripts/run_explain.py` 和 `scripts/build_cases.py` 都支持 `--version <V>`，默认 v1。每个版本独立放在 `benchmark/<version>/` 子目录下，包含输入（`queries.*`）+ Stage A 产物（`explains/`）+ Stage B 产物（`cases/` + `case_index.json` + `trigger_coverage.md`）。新增版本只加一个 `benchmark/v2/` 目录，与 v1 完全隔离。
- **queries 与 ogexplain-analyzer 的关系**：ogagila 的 benchmark 提供 ground-truth 数据集，评估 EXPLAIN 诊断工具（如 ogexplain-analyzer）的准确率。评估器（`evaluate.py`）不在本仓库 — 见 ogexplain-analyzer 项目。
- **case JSON 的 `ogexplain_rule_id` 字段**：引用 ogexplain-analyzer 定义的 25 条诊断规则体系。该字段名是外部规则命名空间引用，不要重命名。
- **不要直接 `gsql < benchmark/v1/queries.sql`** — 该文件含副作用语句（SET/DELETE STATISTICS/UPDATE），会污染后续 query 的执行环境。必须用 `scripts/run_explain.py`（每条 query 在独立 BEGIN/ROLLBACK 内）。
- **数仓分层（DIM/DWD/DWS/ADS + 披露）设计依据**：`.sisyphus/plans/opengauss-tiered-reporting.md`。包含 24 条实测平台约束（G18~G41，如 `::date` 不做日截断、列存不支持 INTERVAL/SPLIT/UNIQUE/FILTER、KVecturbo 使企业版无法在 Apple Silicon 运行）与对官方文档的 3 处修正（向量化引擎/列存窗口函数/`FILTER`）。
- **企业版验证套件 `qa-enterprise.sh`**：V1（O1/O3 裁定）/V15/SMP/Codegen 验证需 x86_64 或鲲鹏（本机 7.0.1 lite 与 5.0.0 均无 SMP，G40 双路确认）。套件带三重防假阳性防线（数据下限 / MIN_BASE_MS / 统一探针 SQL）。
- **极简版/企业版获取与部署**：操作指引见 `sqls/dw/docs/enterprise-smp-verification.md`（官网人工下载极简版二进制 + 单节点部署 + SMP 自检 + 套件运行 + 结果回写）。极简版核心包无法脚本化获取（OBS 列举被拒/JS 渲染），需人工从下载页点击。

## TDD 说明（仅 benchmark 脚本适用）

本仓库不是应用代码仓库——核心是 SQL schema/数据 + Docker 编排，没有单元测试框架。TDD 只适用于 `benchmark/scripts/` 下的 Python 工具脚本（`run_explain.py`、`build_cases.py` 等）。

- 改 `benchmark/scripts/*.py` 前：先写能复现当前行为（输入 query → 输出 case/explain 物料）的特征测试，锁定 `benchmark/v1/`、`v2/`、`v3/` 三个版本目录的产物格式（三者当前各 97 条 case，格式必须保持一致）。
- 新增/修改 ground-truth 生成逻辑（`build_cases.py`）或 EXPLAIN 采集逻辑（`run_explain.py`）时：先有失败的行为断言（例如「给定 query 元数据，生成的 case JSON 必须符合 `benchmark/groundtruth.schema.json`」），再改脚本。
- 禁止：删/改已有的 ground-truth case（`v1`/`v2`/`v3` 各 97 条 `OGEXP-GT-*.json`）或 `queries.sql` 的 `@id/@target/@severity/@scenario` 标记来迁就脚本；`case_index.json`、`trigger_coverage.md` 是生成产物，应重新生成而不是手改。
- schema/数据（`sqls/`）改动不做 TDD，但必须保证 `ON_ERROR_STOP=1` 下 Docker 初始化干净启动（`docker-compose down -v && docker-compose up -d`）。
- 汇报时说明：改了哪个脚本、加了什么特征测试、验证命令与结果。
