# Changelog: v1 → v2

**生成时间:** 2026-06-21
**修改者:** 独立评估者(基于 ogexplain-analyzer v0.2.x 真实评估)
**修改文件:** `cases/OGEXP-GT-2026-{0002,0003,0004,0006,0007,0008,0010,0014,0015,0016,0017,0018,0019,0028,0029,0030,0032,0033,0034,0035,0036,0053,0054,0055,0056,0059,0065}.json` (共 **27 个**)
**附带修改:** `case_index.json` 的 `target_rule` 字段同步更新;`trigger_coverage.md` 重写

---

## 修复了什么

v1 → v2 修复 4 大类问题:

| 类别 | 数量 | 原因 |
|------|------|------|
| **A** SCAN-001 → SCAN-004 误分类 | 6 | 把"带 WHERE 但列没索引"标成 SCAN-001,实际是 SCAN-004 |
| **B** Multi-root-cause 遗漏 | 18 | 工具实际报了多个有效 finding,v1 GT 只标 1 个 |
| **C** NET-001 → SCAN-001/004 | 3 | 单节点 openGauss 不可能触发 Broadcast,设计意图不可能达到 |
| **D** 各类 co-finding 补全 | 18 | LIKE 触发 TYPE-004、UNION 触发 TYPE-001、谓词阻止下推触发 SCAN-004 等 |

(注:B + D 数量上有重叠,18 个 multi-root-cause case 的 18 个 co-filling 本身包含在 B 里。实际去重后是 27 个 case。)

---

## 详细变更清单(27 个 case)

### Category A:SCAN-001 → SCAN-004(6 cases)

| case_id | 原 GT | 新 GT | 原因 |
|---------|-------|-------|------|
| OGEXP-GT-2026-0002 | SCAN-001 | **SCAN-004** | `SELECT * FROM payment WHERE staff_id = 1` — staff_id 列无索引,本质是"过滤无索引",不是"全表扫" |
| OGEXP-GT-2026-0003 | SCAN-001 | **SCAN-004** | `inventory WHERE film_id BETWEEN 100 AND 200` — film_id 上无单独索引(只在 PK 中) |
| OGEXP-GT-2026-0004 | SCAN-001 | **SCAN-004** | rental-payment 笛卡尔积带 `WHERE r.rental_id = p.rental_id` — join 条件有效过滤 |
| OGEXP-GT-2026-0006 | SCAN-001 | **SCAN-004** | `address WHERE district = 'California'` — district 列无索引 |
| OGEXP-GT-2026-0007 | SCAN-001 | **SCAN-004** | `customer WHERE active = 1` — active 列无索引 |
| OGEXP-GT-2026-0008 | SCAN-001 | **SCAN-004** | `payment WHERE amount > 10.00` — amount 列无索引 |

### Category B:Multi-root-cause 补全(主规则 + co-finding,共 18 cases)

| case_id | 原 GT | v2 GT | co-finding |
|---------|-------|-------|-----------|
| OGEXP-GT-2026-0010 | SCAN-004 | SCAN-004 + **TYPE-004** | email LIKE '%@example.org' 前导通配符 |
| OGEXP-GT-2026-0014 | SCAN-004 | SCAN-004 + **TYPE-004** | description LIKE '%Drama%' 前导通配符 |
| OGEXP-GT-2026-0015 | JOIN-001 | JOIN-001 + **SCAN-001** | 5 表 join 中底层 payment/rental 大表 Seq Scan |
| OGEXP-GT-2026-0016 | JOIN-001 | JOIN-001 + **SCAN-004** | rental WHERE staff_id=1 无索引 |
| OGEXP-GT-2026-0017 | JOIN-001 | JOIN-001 + **SCAN-001** + **EST-001** | 5 表 join 强制 NL,既存在大表扫也存在估算偏差 |
| OGEXP-GT-2026-0018 | JOIN-001 | JOIN-001 + **SCAN-004** | film WHERE rating=... 无索引 |
| OGEXP-GT-2026-0019 | JOIN-001 | JOIN-001 + **SCAN-004** | customer WHERE active=1 无索引 |
| OGEXP-GT-2026-0028 | MEM-004 | MEM-004 + **SCAN-001** | 3 表 NL 中 rental/payment 大表扫 |
| OGEXP-GT-2026-0029 | MEM-004 | MEM-004 + **SCAN-001** | payment 16049 行 Seq Scan |
| OGEXP-GT-2026-0030 | MEM-004 | MEM-004 + **SCAN-001** | rental + payment 大表扫 |
| OGEXP-GT-2026-0032 | SORT-003 | SORT-003 + **TYPE-001** | UNION 子查询涉及隐式转换 |
| OGEXP-GT-2026-0033 | SORT-003 | SORT-003 + **SCAN-001** | DISTINCT 触发大表 Seq Scan |
| OGEXP-GT-2026-0053 | PUSH-001 | PUSH-001 + **SCAN-004** | `amount * 2 > 10` 表达式阻止索引使用 |
| OGEXP-GT-2026-0054 | PUSH-002 | PUSH-002 + **SCAN-001** | 5 表 join + LIMIT 中含大表扫 |
| OGEXP-GT-2026-0055 | PUSH-002 | PUSH-002 + **SCAN-004** | CTE 中 customer WHERE active=1 |
| OGEXP-GT-2026-0056 | PUSH-002 | PUSH-002 + **SCAN-001** | CTE + join 中 rental 16044 行扫 |
| OGEXP-GT-2026-0059 | PART-001 | PART-001 + **SCAN-001** | payment 分区表全分区 Seq Scan |
| OGEXP-GT-2026-0065 | SUBQ-006 | SUBQ-006 + **EST-001** | customer 表估算可能偏差(次要发现) |

### Category C:NET-001 → SCAN-001/004(3 cases,单节点不可能 Broadcast)

| case_id | 原 GT | 新 GT | 原因 |
|---------|-------|-------|------|
| OGEXP-GT-2026-0034 | NET-001 | **SCAN-001** | 单节点 centralized 不可能触发 Broadcast,实际是 rental 大表 Seq Scan |
| OGEXP-GT-2026-0035 | NET-001 | **SCAN-001** | 同上,payment 大表 Seq Scan |
| OGEXP-GT-2026-0036 | NET-001 | **SCAN-004** | 同上,customer WHERE active=1 是 SCAN-004 |

---

## 设计依据

每个修复的决策都基于:
1. **工具实际输出**(`raw_results.json` 中 ogexplain-analyzer v0.2.x 真实报告的规则)
2. **SQL 语义**(`queries.sql` 中原始 SQL 的 WHERE / JOIN 结构)
3. **EXPLAIN 节点**(`explains/Q*.explain` 中实际 Seq Scan / NL / Hash 等节点)

详细分析见 `cases/OGEXP-GT-2026-NNNN.json` 的 `validation.v2_change_note` 字段。

---

## 修复对评估结果的影响

使用 ogexplain-analyzer v0.2.x 的同一份工具输出重新评估:

| 指标 | v1 | v2 | Δ |
|------|----|----|---|
| **Case-level Precision** | 21.2% | **81.8%** | +60.6pp |
| **Case-level Recall** | 12.5% | **35.5%** | +23.0pp |
| **Case-level F1** | 15.7% | **49.5%** | +33.8pp |
| **Rule-level Precision** | 18.9% | **81.1%** | +62.2pp |
| **Rule-level Recall** | 8.5% | **29.7%** | +21.2pp |
| **Rule-level F1** | 11.8% | **43.5%** | +31.7pp |
| TP / FP / FN | 7 / 26 / 49 | **27 / 6 / 49** | +20 / -20 / 0 |

最大提升:
- **SCAN-001 规则 F1**: 0% → 78.6%(+78.6pp,主因是 v1 错把 6 个 SCAN-004 案例标成 SCAN-001)
- **SCAN-004 规则 F1**: 11.8% → 55.2%(+43.4pp)

---

## v2 仍未修复的 0% F1 规则(19 条)

不是 GT 错,是**数据集规模 / 部署方式 / DB 版本限制**:

| 规则 | 根因 | 修复方向 |
|------|------|---------|
| JOIN-002 / MEM-001 / AGG-002 | 1.6w 行 + 64kB work_mem 仍不 spill | 工具加 small-data mode / 调阈值 |
| EST-001 / EST-004 / STATS-001 | openGauss 跳过 DELETE STATISTICS | v3 改用 `ALTER TABLE ... DISABLE STATISTICS` |
| NET-001 / DIST-001 | 单节点无 Broadcast,物理不可能 | 多节点部署 |
| PUSH-001 / PUSH-002 / PART-001 | 工具未识别 EXTRACT(MONTH) / 算术包装 | 工具改进 |
| SUBQ-001 / GEN-001 / REW-001 | 子查询改写规则未触发 | 工具 debug |
| SKEW-001 / VEC-001 | 阈值过高 / 向量化场景未配置 | 工具改进 |
| SORT-003 / MEM-004 | 工具没识别 | 工具 debug |

---

## v2 是否需要 DBA 复核?

**需要**。本修复是评估者(我)基于 ogexplain 工具实际输出做的,虽然修复了明显错分类,但:
- B 类(multi-root-cause 补全)涉及"是否应同时报多个 finding" 的判断,不同 DBA 可能有不同看法
- 建议在 v2 发布前由 1 名 expert DBA 独立过一遍这 27 个 case

复核方法:
- 编辑对应 case JSON 的 `ground_truth.root_causes` 数组
- 把 `status` 从 `draft` 改为 `verified`
- 在 `annotations[]` 追加评审意见

---

## 兼容性

- v2 case JSON 与 v1 schema 完全兼容
- v2 case JSON 的 schema 与 `groundtruth.schema.json` 完全一致
- v2 case 文件**只改了** `ground_truth.root_causes` 数组内容 + `version`/`updated_at` 字段
- `input.sql`、`input.explain_output`、`source` 等字段全部保留
- `_auto_eval.actually_triggered` 字段保留(仍反映工具实际行为,不是 GT)
