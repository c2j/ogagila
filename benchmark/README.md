# Benchmark

> openGauss EXPLAIN 评估套件：精心设计的 SQL 查询集 + 真实 EXPLAIN ANALYZE 输出 + 结构化 ground-truth case JSON，
> 供任何 openGauss EXPLAIN 诊断工具（如 [ogexplain-analyzer](https://github.com/c2j/ogexplain-analyzer)）做准确率评估。

## 目录结构

```
benchmark/
├── README.md                       ← 本文件（唯一总文档）
├── scripts/                        ← Python 工具
│   ├── run_explain.py              ← Stage A：跑 EXPLAIN ANALYZE
│   ├── build_cases.py              ← Stage B：合成 ground-truth case
│   └── apply_v2_fixes.py           ← ⛔ ONE-TIME：从 v1 复制并修 27 个 case → v2（跑后可删）
├── groundtruth.schema.json         ← case JSON Schema (Draft 2020-12)
├── v1/                             ← v1 数据集（baseline）
    ├── queries.sql                 ← 输入：SQL 源（含 -- @id / -- @target 标记）
    ├── queries.md                  ← 输入：该版本的人类可读说明
    ├── queries_meta.json           ← 输入：机器可读元数据
    ├── explains/                   ← Stage A 产物：EXPLAIN ANALYZE 输出
    │   ├── index.json
    │   └── Q*.{explain, meta.json}
    ├── cases/                      ← Stage B 产物：ground-truth case JSON
    │   └── OGEXP-GT-2026-NNNN.json
    ├── case_index.json             ← Stage B 汇总：case 索引
    └── trigger_coverage.md         ← Stage B 汇总：触发率报告
└── v2/                             ← ⭐ 推荐评估用：修复了 27 个 GT 错 + 补全 multi-root-cause
    ├── CHANGELOG_v1_to_v2.md       ← v1→v2 详细变更列表（27 个 case）
    ├── cases/                      ← 97 个修正后的 case JSON
    ├── case_index.json             ← target_rule 已同步
    └── trigger_coverage.md         ← v2 的触发率报告
```

> **重要:** v2 是从 v1 手工 + 一次性脚本修过的**最终数据集**。不要在 v2 目录上跑 `build_cases.py --version v2`,会覆盖手修的 27 个 case。v3 之后可以正常用 build_cases.py。

输入（`queries.*`）、Stage A 产物（`explains/`）、Stage B 产物（`cases/` + 汇总）按版本完整隔离，新增版本只加一个 `vX/` 目录。

## 流程总览

```
                    启动 ogagila 容器（pagila schema）
                                ↓
benchmark/v1/queries.sql  →  scripts/run_explain.py        →  benchmark/v1/explains/
                                         [Stage A]                  ↓
                                                          scripts/build_cases.py
                                                                   [Stage B]
                                                                    ↓
                                                          benchmark/v1/cases/
                                                          + case_index.json
                                                          + trigger_coverage.md
```

## 用法

### 1. 启动 ogagila 容器

```bash
docker-compose up -d
```

详见仓库根 [`README.md`](../README.md)。

### 2. Stage A — 跑 EXPLAIN ANALYZE

```bash
pip install psycopg2-binary

# 默认 v1（自动读写 benchmark/v1/）
python3 benchmark/scripts/run_explain.py \
    --host localhost --port 5432 \
    --db pagila --user gaussdb --password Enmo@123
```

脚本行为：

- 对每条 query 自动 `BEGIN; EXPLAIN ANALYZE ...; ROLLBACK;`（避免副作用污染）
- 保存到 `benchmark/v1/explains/Q*.explain` + `.meta.json`
- 同时输出 `explains/index.json`

**注意**：不要直接 `gsql < queries.sql`！文件含副作用语句（SET / DELETE STATISTICS / UPDATE），会污染后续 query 的执行环境。必须用 `run_explain.py`。

### 3. Stage B — 生成 ground-truth case JSON

```bash
# 默认 v1
python3 benchmark/scripts/build_cases.py
```

默认输入：
- `benchmark/v1/queries_meta.json`
- `benchmark/v1/explains/Q*.explain` + `Q*.meta.json`

默认输出（全部落在 `benchmark/v1/` 下）：
- `benchmark/v1/cases/OGEXP-GT-2026-NNNN.json`（97 个）
- `benchmark/v1/case_index.json`
- `benchmark/v1/trigger_coverage.md`

## 多版本机制

加 `--version` / `-V` 切换 query set 版本，所有路径自动推导：

```bash
# Stage A
python3 benchmark/scripts/run_explain.py --version v2

# Stage B
python3 benchmark/scripts/build_cases.py --version v2
```

加 v2 时只新增 `benchmark/v2/` 一个目录，与 v1 完全隔离；清理也是 `rm -rf benchmark/v2/` 一行。

显式 `--meta` / `--sql` / `--out` / `--explains-dir` / `--output-dir` 优先于 `--version` 推导，用于完全自定义路径。

## Case 结构

每个 case JSON 遵循 `groundtruth.schema.json`，核心字段：

| 字段 | 说明 |
|------|------|
| `case_id` | `OGEXP-GT-{YEAR}-{NNNN}` 全局唯一 ID |
| `input.sql` | 原始 SQL |
| `input.explain_output` | 真 EXPLAIN ANALYZE 输出 |
| `input.plan_actual_runtime_ms` | 实测运行时间 (ms) |
| `ground_truth.is_problematic` | 是否有性能问题 |
| `ground_truth.root_causes[]` | 自动推断的根因（待 DBA 复核） |
| `ground_truth.suggested_fixes[]` | 默认修复模板 |
| `_auto_eval` | 自动评估的规则触发情况（启发式判断，非 ground truth） |

查看单个 case：

```bash
cat benchmark/v1/cases/OGEXP-GT-2026-0001.json | python3 -m json.tool
```

`ogexplain_rule_id` 字段引用的是 ogexplain-analyzer 定义的 25 条诊断规则体系；该字段名是外部规则命名空间引用，**不要重命名**。但本数据集本身对任何 openGauss EXPLAIN 解析器都通用。

## v1 当前覆盖

97 个 case（82 problematic + 15 healthy），覆盖 ogexplain-analyzer v0.2.x 25 条规则中的 17 条。

详见：
- [`v1/queries.md`](v1/queries.md) — 规则覆盖表、副作用清单、数据规模
- [`v1/trigger_coverage.md`](v1/trigger_coverage.md) — 每条规则的 designed vs actually_triggered 统计

## v2 修复概要

v2 在 v1 基础上**修了 27 个 case 的 ground-truth 错** + 补全了 18 个 case 的多根因(multi-root-cause):

| 类别 | 数量 | 说明 |
|------|------|------|
| A. SCAN-001 → SCAN-004 | 6 | 6 个 `WHERE 但无索引` 错标 SCAN-001 |
| B. Multi-root-cause 补全 | 18 | 1 个 case 可同时有多个根因 |
| C. NET-001 → SCAN-001/004 | 3 | 单节点不可能 Broadcast |
| D. PUSH-/SORT-/LIKE co-finding | 嵌入 B | 谓词阻止下推、LIKE 前缀、UNION 隐式转换等 |

修复后评估(同一份 ogexplain 工具输出):
- case-level F1: 15.7% → **49.5%** (+33.8pp)
- rule-level F1: 11.8% → **43.5%** (+31.7pp)
- SCAN-001 规则 F1: 0% → **78.6%**

详细变更见 [`v2/CHANGELOG_v1_to_v2.md`](v2/CHANGELOG_v1_to_v2.md)。

**使用 v2 评估**:
```bash
python3 evaluate.py --mode live \
    --cases /path/to/ogagila/benchmark/v2/cases/ \
    --ogexplain-binary target/release/ogexplain
```

## 扩展指南

### 新增 query set 版本（v3、v4...）

```bash
# 1. 复制 v2/ 结构(或 v1/,如果你不需要 v2 的修复)
mkdir -p benchmark/v3
cp benchmark/v2/queries.sql benchmark/v2/queries.md benchmark/v2/queries_meta.json benchmark/v3/
# 然后编辑这三个文件加入新 query

# 2. Stage A：跑 EXPLAIN
python3 benchmark/scripts/run_explain.py --version v3

# 3. Stage B：生成 case
python3 benchmark/scripts/build_cases.py --version v3

# **不要在 v2 上跑 build_cases.py!** v2 已经被手修过 27 个 case,会覆盖修复。
```

### 新增规则映射

先在 ogexplain-analyzer 里定义规则 ID，再在 `scripts/build_cases.py` 的 `RULE_TO_CAUSE_CATEGORY` / `DEFAULT_FIX_TEMPLATES` 加默认映射。

### DBA 复核

编辑 `cases/*.json` 的 `ground_truth` / `annotations` / `validation` 字段，把 `status` 从 `draft` 改为 `verified`。

## 关键 caveat

1. **同作者偏差**：ogagila 与 ogexplain-analyzer 都是 c2j 维护。schema 设计可能恰好让工具的规则更容易触发。
2. **openGauss 7.0.0-RC1 不是 LTS**：生产多用 5/6 版本，执行计划细节可能不同。
3. **数据规模偏小**：payment/rental 各 ~16K 行，阈值型规则即使触发也不会很严重。
4. **单节点 centralized 模式**：ogagila Docker 是单节点 lite build，DIST-/SKEW-/NET-001 等分布式专属规则物理上无法真正触发。
5. **9 条 EST/STATS query 的副作用被跳过**：openGauss 不支持 DELETE STATISTICS 语法。

## 已知局限

- `_auto_eval.actually_triggered` 是启发式判断，不是 ground truth。DBA 复核时若与此字段不一致，以 DBA 为准。
- `trigger_coverage.md` 中 "Skipped" 列包含两类：物理上无法触发 + 检测器找不到信号。

## 评估集成（外部）

本仓库只负责生成 ground-truth 数据集。如果要做诊断工具准确率评估（P/R/F1 报告、混淆矩阵等），见 ogexplain-analyzer 项目的 `evaluate.py`：

```bash
# 在 ogexplain-analyzer 仓库内（不在本仓库）
python3 evaluate.py --mode live \
    --cases /path/to/ogagila/benchmark/v1/cases/ \
    --ogexplain-binary target/release/ogexplain
```
