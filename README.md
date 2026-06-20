# Pagila (openGauss)

[Pagila] （https://github.com/devrimgunduz/pagila）是 [Sakila](https://dev.mysql.com/doc/sakila/en/) 示例数据库的 PostgreSQL 移植版，本项目将其进一步迁移到 **openGauss** 数据库（Oracle 兼容模式）。

原始 Pagila 由 Mike Hillyer (MySQL AB) 开发，用于在书籍、教程、文章中提供标准示例 schema。

## 与原始 Pagila 的主要差异

从 PostgreSQL 迁移到 openGauss 时做了以下适配：

- **分区语法重写**：PG 的 `ATTACH PARTITION ... FOR VALUES FROM ... TO ...` → openGauss 内联 `VALUES LESS THAN`
- **DOMAIN 类型移除**：openGauss 不支持 `CREATE DOMAIN`，`year` 域改为 `integer`，`bıgınt` 域删除
- **`operator(pg_catalog.||)` 改写**：openGauss 不支持 schema 限定操作符语法，改为普通 `||`
- **IDENTITY 列改写**：`GENERATED ALWAYS AS IDENTITY` → `CREATE SEQUENCE` + `nextval` 默认值
- **`phone`/`district` 列改为可空**：Oracle 兼容模式下空字符串等价于 NULL
- **OWNER 统一为 `gaussdb`**：原始 `OWNER TO postgres` 全部替换
- **分区索引/FK 提升到父表**：openGauss 内联分区不暴露为独立表
- **JSONB 数据格式转换**：二进制 `pg_dump -Fc` 备份 → 纯 SQL 文本格式

## 快速开始

### Docker Compose（推荐）

```bash
docker-compose up -d
```

首次启动时，空容器会自动完成全部初始化（约 4 秒）：

1. 创建 openGauss 实例 + `pagila` 数据库
2. 加载 schema（表、函数、触发器、索引、视图）
3. 加载 JSONB 表结构
4. 导入全部业务数据（COPY 格式）
5. 导入 JSONB 包数据

```bash
# 连接数据库（推荐）
docker exec -it pagila gsql-pagila

# 执行单条 SQL
docker exec pagila gsql-pagila -c "SELECT count(*) FROM film;"

# 执行 SQL 文件
docker exec pagila gsql-pagila -f /path/to/script.sql

# 也可以通过 omm 用户直接使用 gsql（无需密码）
docker exec -it pagila bash -c "su - omm -c 'gsql -d pagila'"

# pgAdmin Web UI
# http://localhost:5050
# 用户名: admin@admin.com  密码: root
# 数据库连接已预配置（用户 gaussdb / 数据库 pagila）
```

> **说明：** `gsql-pagila` 是容器内的包装脚本，自动注入用户名 (`gaussdb`) 和密码。openGauss 安全插件要求非 `omm` 用户必须密码认证，因此直接使用 `gsql -d pagila` 需要手动输入密码（`-W Enmo@123`）。

### 手动加载

```bash
# 创建数据库
gsql -d postgres -c "CREATE DATABASE pagila;"

# 按顺序加载：DDL → 存储程序 → 数据
gsql -d pagila -f sqls/ddl/schema.sql
gsql -d pagila -f sqls/ddl/schema-jsonb.sql
gsql -d pagila -f sqls/program/functions.sql
gsql -d pagila -f sqls/program/triggers.sql
gsql -d pagila -f sqls/program/views.sql
gsql -d pagila -f sqls/init_data/data.sql
gsql -d pagila -f sqls/init_data/data-apt-jsonb.sql
gsql -d pagila -f sqls/init_data/data-yum-jsonb.sql
```

## 示例查询

### 查找逾期未还

```sql
SELECT
    CONCAT(customer.last_name, ', ', customer.first_name) AS customer,
    address.phone,
    film.title
FROM rental
    INNER JOIN customer ON rental.customer_id = customer.customer_id
    INNER JOIN address ON customer.address_id = address.address_id
    INNER JOIN inventory ON rental.inventory_id = inventory.inventory_id
    INNER JOIN film ON inventory.film_id = film.film_id
WHERE rental.return_date IS NULL
    AND rental_date < CURRENT_DATE
ORDER BY title
LIMIT 5;
```

### 全文检索

```sql
SELECT title FROM film WHERE fulltext @@ to_tsquery('fate&india');
```

### 分区表查询

`payment` 表按月分区（7 个分区：2022 年 1-7 月），openGauss 自动进行分区裁剪：

```sql
SELECT count(*) FROM payment WHERE payment_date >= '2022-03-01' AND payment_date < '2022-04-01';
```

### JSONB 查询

```sql
SELECT aptdata->'Package' AS package, aptdata->'Version' AS version
FROM packages_apt_postgresql_org
LIMIT 5;
```

## Schema 概览

| 对象类型 | 数量 | 说明 |
|----------|------|------|
| 表 | 15 + 2 JSONB | actor, film, customer, rental, payment (分区表) 等 |
| 视图 | 7 + 1 物化视图 | actor_info, customer_list, film_list 等 |
| 函数 | 10 | film_in_stock, rewards_report, last_day 等（含 1 个自定义聚合） |
| 触发器 | 15 | 14 个 last_update 自动更新 + 1 个全文检索触发器 |
| 分区 | 7 | payment_p2022_01 ~ payment_p2022_07 |

ER 图见 `pagila-schema-diagram.png`。

## Docker 配置

| 配置项 | 值 |
|--------|-----|
| 镜像 | `opengauss/opengauss:latest` |
| 端口 | 5432 (openGauss) / 5050 (pgAdmin) |
| 数据库 | `pagila`（通过 `GS_DB` 自动创建） |
| 用户 | `gaussdb` / 密码: `Enmo@123` |
| 兼容模式 | Oracle (`A`) |

## 文件说明

```
ogagila/
├── docker-compose.yml
├── docker/
│   └── gsql-wrapper.sh              # gsql 包装脚本（自动注入用户名密码）
├── sqls/
│   ├── ddl/                         # DDL：表、序列、类型、约束、索引
│   │   ├── schema.sql
│   │   └── schema-jsonb.sql         # JSONB 扩展表
│   ├── program/                     # 存储程序：函数、触发器、视图
│   │   ├── functions.sql            # 函数 + 自定义聚合
│   │   ├── triggers.sql             # 触发器
│   │   └── views.sql                # 视图 + 物化视图
│   └── init_data/                   # 初始数据
│       ├── data.sql                 # 业务数据（COPY 格式）
│       ├── data-apt-jsonb.sql       # apt 包 JSONB 数据
│       └── data-yum-jsonb.sql       # yum 包 JSONB 数据
├── pgadmin/                         # pgAdmin4 预配置
└── pagila-schema-diagram.png        # ER 图
```

## 许可证

PostgreSQL License — 见 `LICENSE.txt`。
