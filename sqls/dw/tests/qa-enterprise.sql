-- Phase 4 / 企业版验证套件 — V1 / V15 / SMP 计时部分（Q1 剩余项）
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §10.2（V1/V15）/ §5.3（O1/O3 裁定依据）
--
-- ⚠️ 运行前提：企业版或极简版 openGauss（G37：Apple Silicon Docker 不可用，
--    需 x86_64 Linux 或鲲鹏等完整 ARM 服务器）。
--    计划捕获（Streaming/dop 算子）由 qa-enterprise.sh 在 shell 层 grep EXPLAIN 输出
--    完成 —— 本实例实测 openGauss 不支持 EXPLAIN 作子查询/CTAS/FOR 数据源，
--    仅能作为独立语句输出文本，故本文件只负责计时与 GUC 探测。
--
-- 用法：CONTAINER=<企业版容器> bash qa-enterprise.sh
-- 判定：E-*/V15-*/TIMING-* 各行 + shell 层的 SMP-1/V1-RESULT 判定。

\set ON_ERROR_STOP off

\echo '===== E-0  环境识别 ====='
SELECT version() AS db_version;
SELECT CASE WHEN count(*) > 0 THEN 'E-0: 企业版/极简版（检测到 dbe_scheduler 或 dbe_task）'
            ELSE 'E-0: lite（无 DBE_SCHEDULER/DBE_TASK，V1/SMP 将输出 SKIP）' END AS edition
  FROM pg_namespace WHERE nspname IN ('dbe_scheduler','dbe_task');

\echo '===== V15  DBE_SCHEDULER 三段式可用性 ====='
SELECT CASE WHEN count(*) > 0
            THEN 'V15-1 PASS: dbe_scheduler schema 存在，函数: '
                 || string_agg(p.proname, ',' ORDER BY p.proname)
            ELSE 'V15-1 SKIP: dbe_scheduler 不存在（lite；调度维持外部触发+PKG_SERVICE）' END AS result
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'dbe_scheduler';
SELECT CASE WHEN count(*) > 0
            THEN 'V15-2: dbe_task 函数: ' || string_agg(p.proname, ',' ORDER BY p.proname)
            ELSE 'V15-2 SKIP: dbe_task 不存在' END AS result
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'dbe_task';

\echo '===== V1  过程内 EXECUTE IMMEDIATE 计时探针（G13 边界）====='
-- G13 的判定依据是"过程内查询是否获得并行"，体现在**耗时差**上：
--   顶层 query_dop=4 明显快于 query_dop=1  -> 并行生效（对照）
--   过程内 EXECUTE IMMEDIATE 无此提速       -> G13 对 EXECUTE IMMEDIATE 同样生效 -> O1
--   过程内同样提速                          -> G13 不覆盖 EXECUTE IMMEDIATE -> 可简化为 O3
-- 计划层面的 Streaming 算子捕获见 qa-enterprise.sh（shell 层 grep EXPLAIN）。
-- 探针 SQL 常量：与下方 TIMING 段的 dop=1/dop=4 探针**完全一致**，
-- 保证 V1 的"过程内 vs 顶层"对比是同一查询（否则耗时差是查询差异而非并行差异）。
CREATE OR REPLACE PROCEDURE dw.qa_v1_exec(p_run_id varchar2) IS
BEGIN
    EXECUTE IMMEDIATE
        'SELECT store_id, category_id, count(*), '
        || 'count(CASE WHEN dq_flag THEN 1 END), '
        || 'sum(CASE WHEN amount > 5 THEN amount ELSE 0 END) '
        || 'FROM dw.dwd_fact_payment GROUP BY 1,2';
    INSERT INTO dw.etl_run_log(run_id, step_name, status)
    VALUES (p_run_id, 'qa_v1_exec', 'OK');
END;
/
\echo '--- 探针过程已创建 dw.qa_v1_exec ---'

\echo '===== TIMING  加速比探针（query_dop=1 vs 4，各跑 5 次取中位）====='
-- 探针必须足够重：lite 上 101 万行多键聚合仅 ~11ms，亚 20ms 计时被连接/解析
-- 噪声主导（同查询两次 0.158ms vs 11.5ms），无法区分"并行"与"噪声"。
-- 故使用多键聚合 + FILTER 风格（最重探针），并由 shell 层强制 base 中位 > 100ms
-- 才采信加速比，否则如实报告 INCONCLUSIVE（防假阳性，V2 已证 lite 无 SMP）。
\timing on
\echo '--- dop=1 五次 ---'
SET query_dop = 1;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
\echo '--- dop=4 五次 ---'
SET query_dop = 4;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
SELECT store_id, category_id, count(*),
       count(CASE WHEN dq_flag THEN 1 END),
       sum(CASE WHEN amount > 5 THEN amount ELSE 0 END)
  FROM dw.dwd_fact_payment GROUP BY 1,2;
\echo '--- 过程内 dop=4 五次 ---'
CALL dw.qa_v1_exec('V1_TIMING');
CALL dw.qa_v1_exec('V1_TIMING');
CALL dw.qa_v1_exec('V1_TIMING');
CALL dw.qa_v1_exec('V1_TIMING');
CALL dw.qa_v1_exec('V1_TIMING');
RESET query_dop;
\timing off

\echo '===== CODEGEN  LLVM 可用性（企业版/极简版特征）====='
SELECT name, setting, source FROM pg_settings
 WHERE name IN ('enable_codegen','codegen_strategy','enable_smp','query_dop');
SET enable_codegen = on;
SELECT 'CODEGEN-1: enable_codegen 已置 on' AS result;
RESET enable_codegen;
