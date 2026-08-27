-- Phase 1 — PKG_DIM：维度层构建
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §5.1 / §5.2 / §5.3
-- 口径依据：sqls/dw/docs/metric-definitions.md §1 §4
--
-- 幂等规则（方案 §5.3）：每个 build 过程先 DELETE 目标范围再 INSERT，全程单事务，
-- 过程内禁止 COMMIT。维表是全量重建，故 DELETE 无 WHERE。

\set ON_ERROR_STOP on
SET check_function_bodies = false;

CREATE OR REPLACE PACKAGE dw.pkg_dim IS
    PROCEDURE build_dim_store(p_period_from date, p_period_to date,
                              p_run_id varchar2, o_rows OUT integer, o_status OUT varchar2);
    PROCEDURE build_dim_staff(p_run_id varchar2, o_rows OUT integer, o_status OUT varchar2);
    PROCEDURE build_dim_film (p_run_id varchar2, o_rows OUT integer, o_status OUT varchar2);
    PROCEDURE build_dim_geo  (p_run_id varchar2, o_rows OUT integer, o_status OUT varchar2);
    PROCEDURE build_all(p_period_from date, p_period_to date, p_run_id varchar2);
END pkg_dim;
/

CREATE OR REPLACE PACKAGE BODY dw.pkg_dim IS

    PROCEDURE build_dim_store(p_period_from date, p_period_to date,
                              p_run_id varchar2, o_rows OUT integer, o_status OUT varchar2) IS
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_dim_store');

        DELETE FROM dw.dim_store;

        -- 门店交易归属走 payment -> rental -> inventory -> store（库存所在物理门店），
        -- 而非 payment.staff_id -> staff.store_id：实测 store_id=2 有交易但无 staff 行
        -- （源库缺陷 D3），走 staff 路径会漏掉该店全部交易。
        INSERT INTO dw.dim_store(
            store_id, store_status, first_business_date, last_business_date,
            inv_cnt, cust_cnt, staff_cnt, pay_cnt, pay_cnt_all_time,
            manager_staff_id, manager_name, mgr_is_orphan,
            city, country, district, period_from, period_to, run_id)
        SELECT s.store_id,
               CASE WHEN m.inv_cnt > 0 AND m.cust_cnt > 0 AND COALESCE(m.pay_cnt,0) > 0 THEN 'ACTIVE'
                    WHEN m.inv_cnt > 0 AND COALESCE(m.pay_cnt,0) = 0                    THEN 'DORMANT'
                    WHEN m.inv_cnt = 0 AND m.cust_cnt = 0                               THEN 'EXCLUDED'
                    ELSE 'UNCLASSIFIED' END,
               m.first_pay, m.last_pay,
               m.inv_cnt, m.cust_cnt, m.staff_cnt,
               COALESCE(m.pay_cnt, 0), COALESCE(m.pay_cnt_all, 0),
               s.manager_staff_id,
               mgr.first_name || ' ' || mgr.last_name,
               mgr.staff_id IS NULL,
               ci.city, co.country,
               COALESCE(NULLIF(a.district, ''), '(未填写)'),
               p_period_from, p_period_to, p_run_id
          FROM public.store s
          LEFT JOIN public.staff   mgr ON mgr.staff_id = s.manager_staff_id
          LEFT JOIN public.address a   ON a.address_id = s.address_id
          LEFT JOIN public.city    ci  ON ci.city_id = a.city_id
          LEFT JOIN public.country co  ON co.country_id = ci.country_id
          LEFT JOIN (
                SELECT s2.store_id,
                       (SELECT count(*) FROM public.inventory i WHERE i.store_id = s2.store_id) AS inv_cnt,
                       (SELECT count(*) FROM public.customer c WHERE c.store_id = s2.store_id)  AS cust_cnt,
                       (SELECT count(*) FROM public.staff st  WHERE st.store_id = s2.store_id)  AS staff_cnt,
                       pp.pay_cnt, pp.first_pay, pp.last_pay, pa.pay_cnt_all
                  FROM public.store s2
                  LEFT JOIN (
                        SELECT i.store_id,
                               count(*)                  AS pay_cnt,
                               min(p.payment_date)::date  AS first_pay,
                               max(p.payment_date)::date  AS last_pay
                          FROM public.payment p
                          JOIN public.rental r    ON r.rental_id = p.rental_id
                          JOIN public.inventory i ON i.inventory_id = r.inventory_id
                         WHERE p.payment_date >= p_period_from
                           AND p.payment_date <  p_period_to
                         GROUP BY i.store_id) pp ON pp.store_id = s2.store_id
                  LEFT JOIN (
                        SELECT i.store_id, count(*) AS pay_cnt_all
                          FROM public.payment p
                          JOIN public.rental r    ON r.rental_id = p.rental_id
                          JOIN public.inventory i ON i.inventory_id = r.inventory_id
                         GROUP BY i.store_id) pa ON pa.store_id = s2.store_id
               ) m ON m.store_id = s.store_id;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_dim_store', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_dim_store', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    PROCEDURE build_dim_staff(p_run_id varchar2, o_rows OUT integer, o_status OUT varchar2) IS
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_dim_staff');
        DELETE FROM dw.dim_staff;

        INSERT INTO dw.dim_staff(staff_id, store_id, full_name, email, active,
                                 pay_cnt, first_pay_date, last_pay_date, run_id)
        SELECT st.staff_id, st.store_id,
               st.first_name || ' ' || st.last_name,
               st.email, st.active,
               COALESCE(pp.pay_cnt, 0), pp.first_pay, pp.last_pay, p_run_id
          FROM public.staff st
          LEFT JOIN (SELECT staff_id, count(*) AS pay_cnt,
                            min(payment_date)::date AS first_pay,
                            max(payment_date)::date AS last_pay
                       FROM public.payment GROUP BY staff_id) pp ON pp.staff_id = st.staff_id;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_dim_staff', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_dim_staff', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    PROCEDURE build_dim_film(p_run_id varchar2, o_rows OUT integer, o_status OUT varchar2) IS
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_dim_film');
        DELETE FROM dw.dim_film;

        INSERT INTO dw.dim_film(film_id, title, category_id, category_name, multi_category,
                                rating, rental_rate, rental_duration, length,
                                language_name, run_id)
        SELECT f.film_id, f.title,
               fc.category_id, c.name, COALESCE(fc.cat_cnt, 0) > 1,
               f.rating::text, f.rental_rate, f.rental_duration, f.length,
               btrim(l.name), p_run_id
          FROM public.film f
          LEFT JOIN (SELECT film_id, min(category_id) AS category_id,
                            count(*) AS cat_cnt
                       FROM public.film_category GROUP BY film_id) fc ON fc.film_id = f.film_id
          LEFT JOIN public.category c ON c.category_id = fc.category_id
          LEFT JOIN public.language l ON l.language_id = f.language_id;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_dim_film', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_dim_film', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    PROCEDURE build_dim_geo(p_run_id varchar2, o_rows OUT integer, o_status OUT varchar2) IS
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_dim_geo');
        DELETE FROM dw.dim_geo;

        INSERT INTO dw.dim_geo(city_id, city, country_id, country, run_id)
        SELECT ci.city_id, ci.city, co.country_id, co.country, p_run_id
          FROM public.city ci JOIN public.country co ON co.country_id = ci.country_id;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_dim_geo', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_dim_geo', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    PROCEDURE build_all(p_period_from date, p_period_to date, p_run_id varchar2) IS
        v_rows   integer;
        v_status varchar2(16);
    BEGIN
        build_dim_geo  (p_run_id, v_rows, v_status);
        build_dim_film (p_run_id, v_rows, v_status);
        build_dim_staff(p_run_id, v_rows, v_status);
        build_dim_store(p_period_from, p_period_to, p_run_id, v_rows, v_status);
    END;

END pkg_dim;
/
