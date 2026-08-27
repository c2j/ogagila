-- Phase 2 — PKG_DWS：汇总层构建
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §5.2 / §5.3 / DD6
-- 口径依据：sqls/dw/docs/metric-definitions.md §3 §4 §7
--
-- 幂等机制与 DWD 一致：DELETE 半开区间 + INSERT，单事务，过程内禁止 COMMIT。
-- 全部指标从 DWD 派生而非回源，保证 DWS 与 DWD 的口径不会分叉。

\set ON_ERROR_STOP on
SET check_function_bodies = false;

CREATE OR REPLACE PACKAGE dw.pkg_dws IS
    PROCEDURE build_sales_day_category(p_date_from date, p_date_to date, p_run_id varchar2,
                                       o_rows OUT integer, o_status OUT varchar2);
    PROCEDURE build_sales_day_staff   (p_date_from date, p_date_to date, p_run_id varchar2,
                                       o_rows OUT integer, o_status OUT varchar2);
    PROCEDURE build_rental_day_store  (p_date_from date, p_date_to date, p_run_id varchar2,
                                       o_rows OUT integer, o_status OUT varchar2);
    PROCEDURE build_sales_month_store (p_date_from date, p_date_to date, p_run_id varchar2,
                                       o_rows OUT integer, o_status OUT varchar2);
    PROCEDURE build_all(p_date_from date, p_date_to date, p_run_id varchar2);
END pkg_dws;
/

CREATE OR REPLACE PACKAGE BODY dw.pkg_dws IS

    PROCEDURE build_sales_day_category(p_date_from date, p_date_to date, p_run_id varchar2,
                                       o_rows OUT integer, o_status OUT varchar2) IS
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_sales_day_category');

        DELETE FROM dw.dws_sales_day_store_category
         WHERE stat_date >= p_date_from AND stat_date < p_date_to;

        -- 口径文档 §4：记录数用 COUNT(*)，去重客户数用 COUNT(DISTINCT ...)。
        -- dq_flag 用 bool_or 上卷：组内任一明细带瑕疵则整组标记，供 ADS 透出。
        --
        -- ⚠️ 条件计数必须写成 count(CASE WHEN ... THEN 1 END)，**不可用
        -- FILTER (WHERE ...)**：实测 FILTER 在**列存表**上报
        -- "variable not found in subplan target list"（行存表上可用）。
        -- DWD/DWS 事实表都是列存，故本包内一律禁用 FILTER。
        INSERT INTO dw.dws_sales_day_store_category(
            stat_date, store_id, store_status, category_id, category_name,
            pay_cnt, amount, customer_cnt, multi_cat_cnt, dq_flag, run_id)
        SELECT stat_date, store_id, store_status, category_id, category_name,
               count(*), sum(amount), count(DISTINCT customer_id),
               count(CASE WHEN multi_category THEN 1 END),
               bool_or(dq_flag), p_run_id
          FROM dw.dwd_fact_payment
         WHERE stat_date >= p_date_from AND stat_date < p_date_to
           AND is_within_cutoff
         GROUP BY stat_date, store_id, store_status, category_id, category_name;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_sales_day_category', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_sales_day_category', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    PROCEDURE build_sales_day_staff(p_date_from date, p_date_to date, p_run_id varchar2,
                                    o_rows OUT integer, o_status OUT varchar2) IS
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_sales_day_staff');

        DELETE FROM dw.dws_sales_day_store_staff
         WHERE stat_date >= p_date_from AND stat_date < p_date_to;

        INSERT INTO dw.dws_sales_day_store_staff(
            stat_date, store_id, store_status, staff_id, pay_cnt, amount, dq_flag, run_id)
        SELECT stat_date, store_id, store_status, staff_id,
               count(*), sum(amount), bool_or(dq_flag), p_run_id
          FROM dw.dwd_fact_payment
         WHERE stat_date >= p_date_from AND stat_date < p_date_to
           AND is_within_cutoff
         GROUP BY stat_date, store_id, store_status, staff_id;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_sales_day_staff', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_sales_day_staff', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    PROCEDURE build_rental_day_store(p_date_from date, p_date_to date, p_run_id varchar2,
                                     o_rows OUT integer, o_status OUT varchar2) IS
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_rental_day_store');

        DELETE FROM dw.dws_rental_day_store
         WHERE stat_date >= p_date_from AND stat_date < p_date_to;

        INSERT INTO dw.dws_rental_day_store(
            stat_date, store_id, store_status, rental_cnt, returned_cnt,
            open_cnt, overdue_cnt, max_overdue_d, dq_flag, run_id)
        SELECT stat_date, store_id, store_status,
               count(*),
               count(CASE WHEN is_returned THEN 1 END),
               count(CASE WHEN NOT is_returned THEN 1 END),
               count(CASE WHEN is_overdue THEN 1 END),
               max(overdue_days),
               bool_or(dq_flag), p_run_id
          FROM dw.dwd_fact_rental
         WHERE stat_date >= p_date_from AND stat_date < p_date_to
           AND is_within_cutoff
         GROUP BY stat_date, store_id, store_status;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_rental_day_store', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_rental_day_store', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    -- 月表的 is_complete_period 按口径文档 §3 判定：只有**数据区间的首月与末月**
    -- 算不完整。这里以 DWD 的实际数据边界为准而非日历，避免把正常月份误标。
    PROCEDURE build_sales_month_store(p_date_from date, p_date_to date, p_run_id varchar2,
                                      o_rows OUT integer, o_status OUT varchar2) IS
        v_first_month date;
        v_last_month  date;
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_sales_month_store');

        SELECT date_trunc('month', min(stat_date))::date,
               date_trunc('month', max(stat_date))::date
          INTO v_first_month, v_last_month
          FROM dw.dwd_fact_payment;

        DELETE FROM dw.dws_sales_month_store
         WHERE stat_month >= date_trunc('month', p_date_from)::date
           AND stat_month <  date_trunc('month', p_date_to)::date;

        INSERT INTO dw.dws_sales_month_store(
            stat_month, store_id, store_status, pay_cnt, amount, customer_cnt,
            is_complete_period, dq_flag, run_id)
        SELECT date_trunc('month', stat_date)::date, store_id, store_status,
               count(*), sum(amount), count(DISTINCT customer_id),
               date_trunc('month', stat_date)::date NOT IN (v_first_month, v_last_month),
               bool_or(dq_flag), p_run_id
          FROM dw.dwd_fact_payment
         WHERE stat_date >= date_trunc('month', p_date_from)::date
           AND stat_date <  date_trunc('month', p_date_to)::date
           AND is_within_cutoff
         GROUP BY date_trunc('month', stat_date)::date, store_id, store_status;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_sales_month_store', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_sales_month_store', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    PROCEDURE build_all(p_date_from date, p_date_to date, p_run_id varchar2) IS
        v_rows   integer;
        v_status varchar2(16);
    BEGIN
        build_sales_day_category(p_date_from, p_date_to, p_run_id, v_rows, v_status);
        build_sales_day_staff   (p_date_from, p_date_to, p_run_id, v_rows, v_status);
        build_rental_day_store  (p_date_from, p_date_to, p_run_id, v_rows, v_status);
        build_sales_month_store (p_date_from, p_date_to, p_run_id, v_rows, v_status);
    END;

END pkg_dws;
/
