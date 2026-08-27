-- Phase 1 — PKG_DQ：数据质量校验
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §附录 A
-- 口径依据：sqls/dw/docs/metric-definitions.md §10 §11
--
-- 闸门语义不对称（这是分层的核心价值）：
--   C1/C2/C3  见 CRITICAL 不阻塞，DWD 行已打 dq_flag，ADS 视图透出 -> 带瑕疵可用
--   C4 披露    0 CRITICAL 才允许 close_period -> 硬阻塞
--
-- 写入用自治事务：主事务回滚后校验结论仍需留存。

\set ON_ERROR_STOP on
SET check_function_bodies = false;

CREATE OR REPLACE PACKAGE dw.pkg_dq IS
    PROCEDURE emit(p_run_id varchar2, p_period varchar2, p_rule varchar2,
                   p_severity varchar2, p_expected text, p_actual text, p_sample text);
    PROCEDURE run_all(p_run_id varchar2, p_date_from date, p_date_to date);
END pkg_dq;
/

CREATE OR REPLACE PACKAGE BODY dw.pkg_dq IS

    PROCEDURE emit(p_run_id varchar2, p_period varchar2, p_rule varchar2,
                   p_severity varchar2, p_expected text, p_actual text, p_sample text) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO dw.dq_check_result(run_id, period, rule_code, severity,
                                       expected, actual, sample_keys)
        VALUES (p_run_id, p_period, p_rule, p_severity, p_expected, p_actual, p_sample);
    END;

    PROCEDURE run_all(p_run_id varchar2, p_date_from date, p_date_to date) IS
        v_period varchar2(16) := to_char(p_date_from, 'YYYY-MM');
        v_n      bigint;
        v_txt    text;
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'dq_run_all');

        -- STORE_NO_DATA：无库存且无客户的门店。源库有 498 家此类行（缺陷 D1），
        -- 若进入对外披露的"门店数"即构成实质性错误陈述（RK1）。
        SELECT count(*) INTO v_n FROM dw.dim_store WHERE store_status = 'EXCLUDED';
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'STORE_NO_DATA', 'WARN', '0',
                 v_n::text, 'store_status=EXCLUDED');
        END IF;

        -- STORE_NO_STAFF：全时段有交易但无 staff 行。必须用 pay_cnt_all_time 而非
        -- pay_cnt：结构性缺陷不能因"当期无交易"被漏报（实测 store_id=2 命中）。
        SELECT count(*), COALESCE(string_agg(store_id::text, ','), '')
          INTO v_n, v_txt
          FROM dw.dim_store WHERE pay_cnt_all_time > 0 AND staff_cnt = 0;
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'STORE_NO_STAFF', 'CRITICAL', '0', v_n::text, v_txt);
        END IF;

        -- STORE_UNCLASSIFIED：口径文档 §1.1 的三态未覆盖"无库存但有客户"，
        -- 落为第四态并告警，等待业务方按 B4 裁定归属。
        SELECT count(*), COALESCE(string_agg(store_id::text, ','), '')
          INTO v_n, v_txt
          FROM dw.dim_store WHERE store_status = 'UNCLASSIFIED';
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'STORE_UNCLASSIFIED', 'WARN', '0', v_n::text, v_txt);
        END IF;

        SELECT count(*), COALESCE(string_agg(store_id::text, ','), '')
          INTO v_n, v_txt
          FROM dw.dim_store WHERE mgr_is_orphan;
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'MGR_ORPHAN', 'CRITICAL', '0', v_n::text, v_txt);
        END IF;

        -- DATE_RANGE_MISMATCH：rental 最大日期超出 payment 最大日期时，
        -- 末期会呈现"有租赁、零收入"的假性收入断崖（口径文档 §2）。
        IF (SELECT max(rental_date) FROM public.rental)
         > (SELECT max(payment_date) FROM public.payment) THEN
            emit(p_run_id, v_period, 'DATE_RANGE_MISMATCH', 'CRITICAL',
                 'max(rental_date) <= max(payment_date)',
                 (SELECT max(rental_date)::text FROM public.rental) || ' > ' ||
                 (SELECT max(payment_date)::text FROM public.payment), NULL);
        END IF;

        -- PERIOD_INCOMPLETE：期间首/末不完整时环比会产出假暴增/假下滑
        -- （实测 2022-02 相对 2022-01 为 +228.46%）。
        --
        -- 只检查**数据区间的首月与末月**，这是口径文档 §3 的原意。早期实现按
        -- "日历完整性"检查（月内是否覆盖到最后一天），在正常业务下会把大量月份
        -- 误报为不完整（实测 31/32 个月命中），噪声淹没真信号。
        SELECT count(*), COALESCE(string_agg(to_char(m, 'YYYY-MM'), ','), '')
          INTO v_n, v_txt
          FROM (SELECT date_trunc('month', payment_date) m,
                       min(payment_date) mn, max(payment_date) mx
                  FROM public.payment
                 WHERE payment_date >= p_date_from AND payment_date < p_date_to
                 GROUP BY 1) t
         WHERE (m = (SELECT date_trunc('month', min(payment_date)) FROM public.payment
                      WHERE payment_date >= p_date_from AND payment_date < p_date_to)
                AND mn > m + interval '1 day')
            OR (m = (SELECT date_trunc('month', max(payment_date)) FROM public.payment
                      WHERE payment_date >= p_date_from AND payment_date < p_date_to)
                AND mx < m + interval '1 month' - interval '1 day');
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'PERIOD_INCOMPLETE', 'WARN', '0', v_n::text, v_txt);
        END IF;

        -- PARTITION_OVERFLOW：MAXVALUE 兜底分区行数应恒为 0，非 0 说明月分区
        -- 没跟上（哨兵失效）。
        SELECT count(*) INTO v_n FROM public.payment PARTITION (payment_pmax);
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'PARTITION_OVERFLOW', 'CRITICAL', '0', v_n::text,
                 'payment_pmax');
        END IF;

        -- AMOUNT_OVERFLOW：源列 numeric(5,2) 上限 999.99，贴顶行提示上游可能被截断。
        SELECT count(*) INTO v_n FROM public.payment
         WHERE payment_date >= p_date_from AND payment_date < p_date_to
           AND amount >= 999.99;
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'AMOUNT_OVERFLOW', 'CRITICAL', '0', v_n::text,
                 'amount >= 999.99');
        END IF;

        -- RECON_DWD_VS_BASE：DWD 与源表逐月笔数/金额对账。这是发现漏抽、
        -- 重复抽取、迟到数据未回补的主要手段。
        SELECT count(*), COALESCE(string_agg(mon, ','), '') INTO v_n, v_txt
          FROM (SELECT to_char(COALESCE(d.m, s.m), 'YYYY-MM') AS mon
                  FROM (SELECT date_trunc('month', stat_date) m, count(*) c, sum(amount) a
                          FROM dw.dwd_fact_payment
                         WHERE stat_date >= p_date_from AND stat_date < p_date_to
                         GROUP BY 1) d
                  FULL JOIN (SELECT date_trunc('month', payment_date) m, count(*) c, sum(amount) a
                               FROM public.payment
                              WHERE payment_date >= p_date_from AND payment_date < p_date_to
                              GROUP BY 1) s ON s.m = d.m
                 WHERE COALESCE(d.c, -1) <> COALESCE(s.c, -1)
                    OR COALESCE(d.a, -1) <> COALESCE(s.a, -1)) x;
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'RECON_DWD_VS_BASE', 'CRITICAL', '0 diff months',
                 v_n::text, v_txt);
        END IF;

        -- SRC_ROW_DELETED：DWD 有但源表已无的行。增量方案原理上无法感知物理删除
        -- （源表 DELETE 无痕迹，缺陷 S4），只能靠此项按期比对兜住。
        SELECT count(*) INTO v_n
          FROM dw.dwd_fact_payment d
         WHERE d.stat_date >= p_date_from AND d.stat_date < p_date_to
           AND NOT EXISTS (SELECT 1 FROM public.payment p WHERE p.payment_id = d.payment_id);
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'SRC_ROW_DELETED', 'WARN', '0', v_n::text, NULL);
        END IF;

        -- DWD_DUPLICATE_KEY：列存表不支持 UNIQUE 索引（psort 限制），
        -- 方案 §5.3 的物理护栏无法落地，改由本规则承担重复检测。
        SELECT count(*) INTO v_n
          FROM (SELECT stat_date, payment_id FROM dw.dwd_fact_payment
                 WHERE stat_date >= p_date_from AND stat_date < p_date_to
                 GROUP BY 1, 2 HAVING count(*) > 1) t;
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'DWD_DUPLICATE_KEY', 'CRITICAL', '0', v_n::text, NULL);
        END IF;

        -- GLOBAL_INDEX_INVALID：分区 ALTER 未声明 UPDATE GLOBAL INDEX 时全局索引
        -- 会失效（G18）。实测确实发生过：payment 上两个 GLOBAL 索引被置为
        -- indisusable=false，需 REINDEX 修复。
        SELECT count(*), COALESCE(string_agg(ic.relname, ','), '') INTO v_n, v_txt
          FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
         WHERE i.indisusable = false;
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'GLOBAL_INDEX_INVALID', 'CRITICAL', '0', v_n::text, v_txt);
        END IF;

        -- FILM_MULTI_CATEGORY：实测 964/1000 部影片属于多个品类，取 min(category_id)
        -- 单一归属会使单品类金额偏差。归属规则待业务方按 B5 裁定。
        SELECT count(*) INTO v_n FROM dw.dim_film WHERE multi_category;
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'FILM_MULTI_CATEGORY', 'WARN', '0', v_n::text,
                 'min(category_id) 单一归属');
        END IF;

        -- STAT_DATE_NOT_TRUNCATED：stat_date 必须是整日零点。
        -- A 兼容模式下 `::date` 不做日截断（只转秒精度并四舍五入），误用会导致
        -- 下游按秒分组、月末行舍入进下月。列存表不支持 CHECK 约束，故只能在此兜住。
        SELECT count(*) INTO v_n FROM dw.dwd_fact_payment
         WHERE stat_date <> date_trunc('day', stat_date);
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'STAT_DATE_NOT_TRUNCATED', 'CRITICAL', '0',
                 v_n::text, 'dwd_fact_payment');
        END IF;
        SELECT count(*) INTO v_n FROM dw.dwd_fact_rental
         WHERE stat_date <> date_trunc('day', stat_date);
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'STAT_DATE_NOT_TRUNCATED', 'CRITICAL', '0',
                 v_n::text, 'dwd_fact_rental');
        END IF;

        -- WATERMARK_STALL：水位线长时间未推进说明增量管线已停摆。
        -- 阈值取 2 天（日调度容忍一次失败），首次运行前 wm 为 NULL 不算停摆。
        SELECT count(*), COALESCE(string_agg(source_name, ','), '') INTO v_n, v_txt
          FROM dw.etl_watermark
         WHERE wm_ts_value IS NOT NULL
           AND updated_at < now() - interval '2 days';
        IF v_n > 0 THEN
            emit(p_run_id, v_period, 'WATERMARK_STALL', 'CRITICAL', '0', v_n::text, v_txt);
        END IF;

        -- YOY_BASE_MISSING：同比基线不足时必须显式标记，
        -- 严禁用 COALESCE(prev_year,0) 填充（会产出 ±∞% 增长率）。
        SELECT count(DISTINCT date_trunc('month', stat_date)) INTO v_n
          FROM dw.dwd_fact_payment;
        IF v_n < 25 THEN
            emit(p_run_id, v_period, 'YOY_BASE_MISSING', 'WARN', '>= 25 months',
                 v_n::text, NULL);
        END IF;

        dw.pkg_etl_core.log_end(p_run_id, 'dq_run_all', 'OK', NULL, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'dq_run_all', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

END pkg_dq;
/
