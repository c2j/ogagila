# PROJECT KNOWLEDGE BASE

**Generated:** 2026-06-20
**Branch:** master

## OVERVIEW

Pagila — Sakila 示例数据库的 openGauss 移植版。从 PostgreSQL 迁移到 openGauss 7.0（Oracle 兼容模式）。Docker Compose 自动初始化 schema + 数据。纯 schema/data/Docker 项目，无应用代码。

## STRUCTURE

```
ogagila/
├── docker-compose.yml                  # openGauss + pgAdmin4 编排
├── pagila-schema-opengauss.sql         # 主 schema：15 表 + 7 视图 + 10 函数 + 15 触发器
├── pagila-schema-jsonb-opengauss.sql   # JSONB 扩展：packages_apt/yum_postgresql_org
├── pagila-data-opengauss.sql           # 业务数据（COPY 格式，payment COPY 重定向到父表）
├── pagila-data-apt-jsonb.sql           # apt 包 JSONB 数据（纯 SQL，67109 行）
├── pagila-data-yum-jsonb.sql           # yum 包 JSONB 数据（纯 SQL，84685 行）
├── pagila-schema-diagram.png           # ER 图参考
├── pgadmin/                            # pgAdmin4 预配置
│   ├── pgadmin_servers.json            # 服务器定义 → 容器 pagila，用户 gaussdb
│   └── pgadmin_pass                    # 密码文件（libpq .pgpass 格式）
├── README.md
└── LICENSE.txt
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| 理解 schema | `pagila-schema-opengauss.sql` | 15 表 + payment 分区表（7 内联分区） |
| JSONB 表 | `pagila-schema-jsonb-opengauss.sql` | 2 表，用 SEQUENCE+nextval 替代 IDENTITY |
| 修改 Docker | `docker-compose.yml` | `GS_DB=pagila` 自动建库，5 个 SQL 文件按序号自动加载 |
| 初始化顺序 | `docker-compose.yml` volumes | 1-schema → 2-schema-jsonb → 3-data → 4-apt → 5-yum |
| pgAdmin 连接 | `pgadmin/pgadmin_servers.json` | Host=pagila, User=gaussdb, DB=pagila |
| 分区定义 | `pagila-schema-opengauss.sql` payment 表 | openGauss 内联 `VALUES LESS THAN` 语法 |

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

## ANTI-PATTERNS (THIS PROJECT)

- **不要使用 `CREATE DOMAIN`** — openGauss 不支持，已用 `integer` + 内联 CHECK 替代
- **不要使用 `GENERATED ALWAYS AS IDENTITY`** — Oracle 兼容模式不支持，用 SEQUENCE + nextval
- **不要使用 `operator(schema.||)` 语法** — openGauss 不支持，用普通 `||`
- **不要使用 PG 分区 ATTACH 语法** — 用 openGauss 内联 `VALUES LESS THAN`
- **不要在 text NOT NULL 列存空字符串** — Oracle 模式下空串= NULL，phone/district 已改为可空
- **不要用 `psql`/`pg_restore`** — 用 `gsql`/`gs_dump`/`gs_restore`
- **不要加载二进制 `.backup` 文件** — JSONB 数据已转为纯 SQL 文本格式
- **开发凭据硬编码** — `GS_PASSWORD: Enmo@123`，pgAdmin: `admin@admin.com` / `root`。不要用于生产。

## COMMANDS

```bash
# 启动（空容器自动初始化全部 schema + 数据）
docker-compose up -d

# 连接数据库
docker exec -it pagila gsql -d pagila

# pgAdmin Web UI
# http://localhost:5050  (admin@admin.com / root)

# 手动加载（非 Docker 场景）
gsql -d postgres -c "CREATE DATABASE pagila;"
gsql -d pagila -f pagila-schema-opengauss.sql
gsql -d pagila -f pagila-schema-jsonb-opengauss.sql
gsql -d pagila -f pagila-data-opengauss.sql
gsql -d pagila -f pagila-data-apt-jsonb.sql
gsql -d pagila -f pagila-data-yum-jsonb.sql

# 停止（保留数据卷）
docker-compose down

# 完全清除（重新初始化）
docker-compose down -v
```

## NOTES

- 仓库名 `ogagila` ≠ 内容 `pagila` — 本地文件夹名，上游为 `devrimgunduz/pagila`
- openGauss 版本：7.0.0-RC1（lite build），Oracle 兼容模式 (`datcompatibility = A`)
- 原始 PG 文件已移除（schema/data/backup/restore 脚本），openGauss 版本为唯一版本
- `pagila-schema-diagram.png` 是静态 ER 参考图 — 非代码生成
- pgAdmin 密码文件格式：`host:port:db:user:password`（libpq `.pgpass` 格式）
- JSONB 数据文件较大（~49MB + ~54MB）— 纯 SQL 文本，无 Git LFS
- Docker 初始化总耗时约 4 秒（不含镜像下载和 initdb）
