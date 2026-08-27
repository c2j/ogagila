-- Phase 2 — PKG_ADS：C1 大屏刷新
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §4.3 / §5.4 / §10.2-V5
--
-- p_mode 取值与两者的读可用性差异见方案 §5.4。选择阈值：单次重建 > 200ms
-- 才值得付出 SWAP 的两套表与中间态代价。默认 REPLACE —— 本实例实测远低于阈值
-- （计时见 qa-phase2-ads.sql）。门店量级上升后按阈值切换，调用方无需改动。

\set ON_ERROR_STOP on
SET check_function_bodies = false;

CREATE OR REPLACE PACKAGE dw.pkg_ads IS
    PROCEDURE build_screen_today(p_date date, p_run_id varchar2,
                                 p_mode varchar2 DEFAULT 'REPLACE',
                                 o_rows OUT integer, o_ms OUT numeric);
END pkg_ads;
/

CREATE OR REPLACE PACKAGE BODY dw.pkg_ads IS

    PROCEDURE build_screen_today(p_date date, p_run_id varchar2,
                                 p_mode varchar2 DEFAULT 'REPLACE',
                                 o_rows OUT integer, o_ms OUT numeric) IS
        v_t0     timestamptz := clock_timestamp();
        v_target varchar2(128);
    BEGIN
        IF p_mode NOT IN ('REPLACE', 'SWAP') THEN
            RAISE_APPLICATION_ERROR(-20030,
                'build_screen_today: p_mode must be REPLACE or SWAP, got ' || p_mode);
        END IF;
        dw.pkg_etl_core.log_start(p_run_id, 'build_screen_today[' || p_mode || ']');

        IF p_mode = 'SWAP' THEN
            -- 影子表用 LIKE 复制结构（含压缩选项），避免与主表 DDL 漂移。
            EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS dw.ads_screen_store_today_new';
            EXECUTE IMMEDIATE 'CREATE TABLE dw.ads_screen_store_today_new '
                              || '(LIKE dw.ads_screen_store_today INCLUDING ALL)';
            v_target := 'dw.ads_screen_store_today_new';
        ELSE
            DELETE FROM dw.ads_screen_store_today WHERE stat_date = p_date;
            v_target := 'dw.ads_screen_store_today';
        END IF;

        -- 全部指标从 DWD/DWS 派生，不回源，保证与其余层口径一致。
        EXECUTE IMMEDIATE
        'INSERT INTO ' || v_target || '(stat_date, store_id, store_name, store_city, '
        || 'pay_cnt, amount, exact_customer_cnt, uv_hll, approx_uv, '
        || 'rental_cnt, open_cnt, overdue_cnt, top_category, dq_flag, run_id) '
        || 'SELECT p.stat_date, p.store_id, ds.city || '' #'' || p.store_id, ds.city, '
        || '       p.pay_cnt, p.amount, p.exact_cnt, p.uv, hll_cardinality(p.uv)::bigint, '
        || '       COALESCE(r.rental_cnt,0), COALESCE(r.open_cnt,0), COALESCE(r.overdue_cnt,0), '
        || '       p.top_cat, p.dq_flag, ' || quote_literal(p_run_id) || ' '
        || 'FROM (SELECT stat_date, store_id, count(*) AS pay_cnt, sum(amount) AS amount, '
        || '             count(DISTINCT customer_id) AS exact_cnt, '
        || '             hll_add_agg(hll_hash_integer(customer_id)) AS uv, '
        || '             max(category_name) AS top_cat, bool_or(dq_flag) AS dq_flag '
        || '        FROM dw.dwd_fact_payment '
        || '       WHERE stat_date = ' || quote_literal(to_char(p_date, 'YYYY-MM-DD'))
        || '         AND store_status = ''ACTIVE'' AND is_within_cutoff '
        || '       GROUP BY stat_date, store_id) p '
        || 'LEFT JOIN dw.dws_rental_day_store r '
        || '       ON r.stat_date = p.stat_date AND r.store_id = p.store_id '
        || 'LEFT JOIN dw.dim_store ds ON ds.store_id = p.store_id';

        o_rows := SQL%ROWCOUNT;

        IF p_mode = 'SWAP' THEN
            -- 单事务内原子切换。持锁时间只覆盖两次 RENAME，远短于重建过程。
            EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS dw.ads_screen_store_today_old';
            EXECUTE IMMEDIATE 'ALTER TABLE dw.ads_screen_store_today '
                              || 'RENAME TO ads_screen_store_today_old';
            EXECUTE IMMEDIATE 'ALTER TABLE dw.ads_screen_store_today_new '
                              || 'RENAME TO ads_screen_store_today';
            EXECUTE IMMEDIATE 'DROP TABLE dw.ads_screen_store_today_old';
        END IF;

        o_ms := round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000, 2);
        dw.pkg_etl_core.log_end(p_run_id, 'build_screen_today[' || p_mode || ']',
                                'OK', o_rows, NULL, NULL);
        RAISE NOTICE 'build_screen_today[%]: % row(s) in % ms', p_mode, o_rows, o_ms;
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_screen_today[' || p_mode || ']',
                                'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

END pkg_ads;
/
