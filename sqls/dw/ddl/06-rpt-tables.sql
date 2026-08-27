-- Phase 3 — C4 披露层四件套
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §4.3 / DD8 / §附录 A
-- 口径依据：sqls/dw/docs/metric-definitions.md 全文（尤其 §1 §5 §11）
--
-- 为什么披露层需要四张表而不是只冻结输出：
-- 源表 payment 无 last_update、其余表的 DELETE 无任何痕迹（缺陷 S3/S4），
-- 意味着 T+30 天无法重现 T 日的源数据状态。因此"可重算"必须靠
-- **冻结输入指纹 + 冻结输出快照 + 冻结口径版本 + 期间锁定** 四者共同保证，
-- 不能靠重扫源表。

\set ON_ERROR_STOP on

-- 口径版本表。所有对外披露指标的定义都必须在此登记并冻结版本号。
-- 这张表同时把口径文档 §1.3/§5.3 的待裁定项（B1~B5）变成**配置**：
-- 业务方裁定后改这里的一行，而不是改存储过程代码。
CREATE SEQUENCE IF NOT EXISTS dw.rpt_metric_def_seq;
CREATE TABLE IF NOT EXISTS dw.rpt_metric_def (
    def_id          bigint       NOT NULL DEFAULT nextval('dw.rpt_metric_def_seq'::regclass),
    metric_code     varchar(64)  NOT NULL,
    version         integer      NOT NULL,
    definition_text text         NOT NULL,
    config_value    text,
    sql_fingerprint varchar(64),
    effective_from  date         NOT NULL,
    approved_by     varchar(64),
    approved_at     timestamp with time zone,
    status          varchar(16)  NOT NULL DEFAULT 'DRAFT',
    created_at      timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT rpt_metric_def_pk PRIMARY KEY (def_id),
    CONSTRAINT rpt_metric_def_uk UNIQUE (metric_code, version),
    CONSTRAINT rpt_metric_def_status_ck CHECK (status IN ('DRAFT','APPROVED','SUPERSEDED'))
) WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);

-- 期间锁定。status 一旦 CLOSED 即不允许再产生同版本快照，
-- 只能通过 recompute_period 产生新的 snapshot_version。
CREATE TABLE IF NOT EXISTS dw.rpt_period_close (
    period             varchar(16) NOT NULL,
    status             varchar(16) NOT NULL DEFAULT 'OPEN',
    metric_def_version integer,
    run_id             varchar(64),
    closed_by          varchar(64),
    closed_at          timestamp with time zone,
    reopened_by        varchar(64),
    reopened_at        timestamp with time zone,
    updated_at         timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT rpt_period_close_pk PRIMARY KEY (period),
    CONSTRAINT rpt_period_close_status_ck CHECK (status IN ('OPEN','CLOSING','CLOSED'))
) WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);

-- 输入指纹。用低成本的聚合特征证明"冻结时的源数据与现在是否一致"，
-- 而不是保存源数据副本。checksum 用 md5 汇总，可发现值改动；
-- row_count / sum_amount / 主键区间可定位改动方向。
CREATE SEQUENCE IF NOT EXISTS dw.rpt_source_fingerprint_seq;
CREATE TABLE IF NOT EXISTS dw.rpt_source_fingerprint (
    fp_id      bigint       NOT NULL DEFAULT nextval('dw.rpt_source_fingerprint_seq'::regclass),
    period     varchar(16)  NOT NULL,
    table_name varchar(128) NOT NULL,
    row_count  bigint       NOT NULL,
    sum_amount numeric(24,4),
    min_pk     bigint,
    max_pk     bigint,
    checksum   varchar(64)  NOT NULL,
    taken_at   timestamp with time zone NOT NULL DEFAULT now(),
    run_id     varchar(64)  NOT NULL,
    CONSTRAINT rpt_source_fingerprint_pk PRIMARY KEY (fp_id)
) WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);
CREATE INDEX IF NOT EXISTS idx_rpt_fp_period
    ON dw.rpt_source_fingerprint (period, table_name, taken_at);

-- 输出快照。(period, snapshot_version, metric_code) 为主键：
-- 重算只产生 snapshot_version + 1 的新行，**永不覆盖旧行**，
-- 这正好对应会计上的追溯重述（原披露值必须可追溯）。
CREATE TABLE IF NOT EXISTS dw.rpt_disclosure_snapshot (
    period             varchar(16)   NOT NULL,
    snapshot_version   integer       NOT NULL,
    metric_code        varchar(64)   NOT NULL,
    metric_value       numeric(24,4),
    metric_text        text,
    metric_def_version integer,
    run_id             varchar(64)   NOT NULL,
    frozen_at          timestamp with time zone NOT NULL DEFAULT now(),
    CONSTRAINT rpt_disclosure_snapshot_pk PRIMARY KEY (period, snapshot_version, metric_code)
) WITH (compresstype=2, compress_chunk_size=1024, compress_level=1);

-- 不可变保护。方案 DD8 要求快照物理不可变：任何 UPDATE/DELETE 都必须失败。
-- 这同时也是源库缺陷 S4（DELETE 无痕迹）在披露层内的补偿 —— 至少快照删不掉。
CREATE OR REPLACE FUNCTION dw.trg_snapshot_immutable() RETURNS trigger AS $$
BEGIN
    RAISE_APPLICATION_ERROR(-20040,
        'rpt_disclosure_snapshot 不可变：禁止 ' || TG_OP
        || '。修正披露请用 PKG_DISCLOSE.recompute_period 产生新 snapshot_version。');
    RETURN NULL;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_snapshot_no_update ON dw.rpt_disclosure_snapshot;
CREATE TRIGGER trg_snapshot_no_update BEFORE UPDATE ON dw.rpt_disclosure_snapshot
    FOR EACH ROW EXECUTE FUNCTION dw.trg_snapshot_immutable();

DROP TRIGGER IF EXISTS trg_snapshot_no_delete ON dw.rpt_disclosure_snapshot;
CREATE TRIGGER trg_snapshot_no_delete BEFORE DELETE ON dw.rpt_disclosure_snapshot
    FOR EACH ROW EXECUTE FUNCTION dw.trg_snapshot_immutable();

-- B1~B5 录入为 DRAFT。这些是口径文档 §1.3 / §5.3 的待业务方裁定项。
-- status 保持 DRAFT 且 approved_by 为空 —— PKG_DISCLOSE.close_period 会检查
-- 是否存在未批准的口径定义，未批准即拒绝冻结（口径不能带着未决问题对外披露）。
INSERT INTO dw.rpt_metric_def(metric_code, version, definition_text, config_value, effective_from, status)
VALUES
 ('STORE_STATUS_RULE', 1,
  'B1/B2/B4：门店状态判定。ACTIVE=有库存+有客户+期间内有交易；DORMANT=有库存但期间内无交易；EXCLUDED=无库存且无客户；UNCLASSIFIED=无库存但有客户（B4 待裁定其归属）。',
  'UNCLASSIFIED_MAPS_TO=UNCLASSIFIED', date '2022-01-01', 'DRAFT'),
 ('STORE_ACTIVE_PERIOD', 1,
  'B3：判定"期间内有交易"所用的期间取值。当前实现由 build_dim_store 的 p_period_from/p_period_to 参数传入。',
  'PERIOD_SOURCE=CALLER_PARAM', date '2022-01-01', 'DRAFT'),
 ('DISCLOSED_STORE_COUNT', 1,
  '对外披露的门店数 = count(*) FROM dim_store WHERE store_status=''ACTIVE''。禁止使用 count(*) FROM store（实测 500 行中仅 2 家有业务，直接使用构成实质性错误陈述）。',
  'INCLUDE_STATUS=ACTIVE', date '2022-01-01', 'DRAFT'),
 ('CATEGORY_ATTRIBUTION', 1,
  'B5：多品类影片的收入归属规则。实测 964/1000 部影片属于多个品类。当前取 min(category_id) 单一归属，各品类金额相加等于总收入，但单品类金额存在偏差。',
  'MODE=SINGLE_MIN', date '2022-01-01', 'DRAFT'),
 ('REVENUE_TOTAL', 1,
  '营业收入 = sum(payment.amount)，仅计入 is_within_cutoff=true 的明细（统一分析截止日见口径文档 §2）。金额列一律 numeric(18,2) 以上精度。',
  'CUTOFF=LEAST(max_payment_date,max_rental_date)', date '2022-01-01', 'DRAFT'),
 ('MOM_YOY_RULE', 1,
  '环比/同比：不完整期间一律返回 NULL；必须先生成完整月份骨架再 LAG；除法一律 NULLIF 保护；严禁 COALESCE(prev,0)。',
  'INCOMPLETE_RETURNS=NULL', date '2022-01-01', 'DRAFT')
ON DUPLICATE KEY UPDATE NOTHING;

SELECT 'rpt tables' AS component,
       CASE WHEN count(*) = 4 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/4)' END AS result,
       string_agg(tablename, ', ' ORDER BY tablename) AS detail
FROM pg_tables WHERE schemaname = 'dw' AND tablename LIKE 'rpt_%'
UNION ALL
SELECT 'metric_def seed',
       CASE WHEN count(*) = 6 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/6)' END,
       'DRAFT: ' || count(*) FILTER (WHERE status = 'DRAFT')
FROM dw.rpt_metric_def
UNION ALL
SELECT 'immutable triggers',
       CASE WHEN count(*) = 2 THEN 'PASS' ELSE 'FAIL (' || count(*) || '/2)' END,
       string_agg(tgname, ', ' ORDER BY tgname)
FROM pg_trigger
WHERE tgrelid = 'dw.rpt_disclosure_snapshot'::regclass AND NOT tgisinternal;
