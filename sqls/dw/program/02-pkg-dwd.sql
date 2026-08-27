-- Phase 1 — PKG_DWD：明细层构建
-- 方案依据：.sisyphus/plans/opengauss-tiered-reporting.md §5.2 / §5.3 / DD6
-- 口径依据：sqls/dw/docs/metric-definitions.md §1 §2 §5
--
-- 幂等机制（DD6）：DELETE 半开区间 + INSERT，全程单事务，过程内禁止 COMMIT。
-- 选 DELETE+INSERT 而非 MERGE 的理由：MERGE 不会删除源侧已删除的行（留幽灵行），
-- 且列存表不支持 ON DUPLICATE KEY UPDATE。
--
-- 参数一律半开区间 [p_date_from, p_date_to)：闭区间会让分区裁剪失效并造成
-- 边界行重复计入相邻两期。
--
-- stat_date 必须用 date_trunc('day', ...) 生成，**绝不可用 ::date**：
-- A 兼容模式下 date 等价于 Oracle DATE（= timestamp(0)），`::date` 不做日截断，
-- 只做"转秒精度 + 四舍五入"。实测后果有两个，都是静默错误：
--   1) 全部行的 stat_date 保留时分秒 -> 下游 GROUP BY stat_date 变成按秒分组
--   2) 月末最后一微秒被舍入进下月
--      (timestamptz '2025-05-31 23:59:59.999999+00' AT TIME ZONE 'UTC')::date
--      = 2025-06-01 00:00:00
-- 列存表不支持 CHECK 约束，故无法物理防护，由 DQ 规则 STAT_DATE_NOT_TRUNCATED 兜住。

\set ON_ERROR_STOP on
SET check_function_bodies = false;

CREATE OR REPLACE PACKAGE dw.pkg_dwd IS
    PROCEDURE build_dwd_fact_payment(p_date_from date, p_date_to date, p_run_id varchar2,
                                     o_rows OUT integer, o_status OUT varchar2);
    PROCEDURE build_dwd_fact_rental (p_date_from date, p_date_to date, p_run_id varchar2,
                                     o_rows OUT integer, o_status OUT varchar2);

    PROCEDURE build_payment_incremental(p_run_id varchar2,
                                        o_rows OUT integer, o_months OUT integer);
    PROCEDURE build_rental_incremental (p_run_id varchar2,
                                        o_rows OUT integer, o_months OUT integer);

    FUNCTION gen_payment_sql(p_date_from date, p_date_to date, p_run_id varchar2) RETURN text;
    FUNCTION gen_rental_sql (p_date_from date, p_date_to date, p_run_id varchar2) RETURN text;
END pkg_dwd;
/

CREATE OR REPLACE PACKAGE BODY dw.pkg_dwd IS

    PROCEDURE build_dwd_fact_payment(p_date_from date, p_date_to date, p_run_id varchar2,
                                     o_rows OUT integer, o_status OUT varchar2) IS
        v_cutoff timestamptz;
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_dwd_fact_payment');

        SELECT analysis_cutoff INTO v_cutoff FROM dw.v_analysis_cutoff;

        DELETE FROM dw.dwd_fact_payment
         WHERE stat_date >= p_date_from AND stat_date < p_date_to;

        -- 门店归属走 rental -> inventory -> store（库存所在物理门店）。
        -- 不走 payment.staff_id -> staff.store_id：实测 store_id=2 有交易但无
        -- staff 行（源库缺陷 D3），走 staff 路径会漏掉该店全部交易。
        --
        -- dq_flag 汇总本行的质量瑕疵，供 ADS 层透出（方案 §附录 A 闸门语义：
        -- C1/C2/C3 带瑕疵可用，C4 披露硬阻塞）。
        INSERT INTO dw.dwd_fact_payment(
            stat_date, payment_ts, payment_id, rental_id, customer_id, staff_id,
            store_id, store_status, film_id, category_id, category_name,
            store_city, store_country, amount, is_within_cutoff, multi_category,
            dq_flag, run_id)
        SELECT date_trunc('day', p.payment_date AT TIME ZONE 'UTC'),
               p.payment_date, p.payment_id, p.rental_id, p.customer_id, p.staff_id,
               i.store_id, ds.store_status,
               i.film_id, df.category_id, df.category_name,
               ds.city, ds.country,
               p.amount::numeric(18,2),
               p.payment_date <= v_cutoff,
               COALESCE(df.multi_category, false),
               (ds.store_id IS NULL)
            OR (ds.store_status IN ('EXCLUDED','UNCLASSIFIED'))
            OR (ds.mgr_is_orphan)
            OR (ds.staff_cnt = 0)
            OR (df.film_id IS NULL)
            OR (p.payment_date > v_cutoff),
               p_run_id
          FROM public.payment p
          LEFT JOIN public.rental r    ON r.rental_id = p.rental_id
          LEFT JOIN public.inventory i ON i.inventory_id = r.inventory_id
          LEFT JOIN dw.dim_store ds    ON ds.store_id = i.store_id
          LEFT JOIN dw.dim_film df     ON df.film_id = i.film_id
         WHERE p.payment_date >= p_date_from
           AND p.payment_date <  p_date_to;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_dwd_fact_payment', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_dwd_fact_payment', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    PROCEDURE build_dwd_fact_rental(p_date_from date, p_date_to date, p_run_id varchar2,
                                    o_rows OUT integer, o_status OUT varchar2) IS
        v_cutoff timestamptz;
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_dwd_fact_rental');

        SELECT analysis_cutoff INTO v_cutoff FROM dw.v_analysis_cutoff;

        DELETE FROM dw.dwd_fact_rental
         WHERE stat_date >= p_date_from AND stat_date < p_date_to;

        -- 逾期判定：未归还且已超出 film.rental_duration。overdue_days 以
        -- 统一分析截止日为基准而非 now()，保证同一期间重算结果稳定（可重算性）。
        --
        -- 天数差用 EXTRACT(EPOCH ...)/86400 而非 date - date：
        -- A 兼容模式下 date - date 返回 interval（标准 PostgreSQL 返回 integer），
        -- 直接参与算术会报 "types integer and interval cannot be matched"。
        INSERT INTO dw.dwd_fact_rental(
            stat_date, rental_ts, rental_id, return_ts, customer_id, staff_id,
            inventory_id, film_id, store_id, store_status, category_id, category_name,
            rental_duration, is_returned, is_overdue, overdue_days,
            is_within_cutoff, dq_flag, run_id)
        SELECT date_trunc('day', r.rental_date AT TIME ZONE 'UTC'),
               r.rental_date, r.rental_id, r.return_date, r.customer_id, r.staff_id,
               r.inventory_id, i.film_id, i.store_id, ds.store_status,
               df.category_id, df.category_name,
               f.rental_duration,
               r.return_date IS NOT NULL,
               r.return_date IS NULL
                 AND LEAST(v_cutoff, now()) > r.rental_date
                     + (f.rental_duration * interval '1 day'),
               CASE WHEN r.return_date IS NULL
                    THEN GREATEST(0,
                           floor(EXTRACT(EPOCH FROM (LEAST(v_cutoff, now()) - r.rental_date))
                                 / 86400)::integer
                           - COALESCE(f.rental_duration, 0))
                    ELSE NULL END,
               r.rental_date <= v_cutoff,
               (ds.store_id IS NULL)
            OR (ds.store_status IN ('EXCLUDED','UNCLASSIFIED'))
            OR (df.film_id IS NULL)
            OR (r.rental_date > v_cutoff),
               p_run_id
          FROM public.rental r
          LEFT JOIN public.inventory i ON i.inventory_id = r.inventory_id
          LEFT JOIN public.film f      ON f.film_id = i.film_id
          LEFT JOIN dw.dim_store ds    ON ds.store_id = i.store_id
          LEFT JOIN dw.dim_film df     ON df.film_id = i.film_id
         WHERE r.rental_date >= p_date_from
           AND r.rental_date <  p_date_to;

        o_rows := SQL%ROWCOUNT;
        o_status := 'OK';
        dw.pkg_etl_core.log_end(p_run_id, 'build_dwd_fact_rental', o_status, o_rows, NULL, NULL);
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_dwd_fact_rental', 'FAILED', 0, SQLSTATE, SQLERRM);
        RAISE;
    END;

    -- 增量入口：双轨识别"受影响的月份"，然后对每个受影响月份**整月重建**。
    --
    -- 为什么是"整月重建"而不是"只写增量行"：
    --   DWD 是列存表，不支持 UNIQUE / ON DUPLICATE KEY UPDATE，只能靠 DELETE+INSERT
    --   保证幂等（DD6）。按月为单位重建使"哪些行变了"这个问题无需精确回答 ——
    --   补录、迟到、更新、删除全部自动被覆盖，且重跑安全。
    --   代价是重建粒度较粗；1 亿行级规模下若单月过大，可在 Phase 4 降级为按日重建
    --   （把 date_trunc('month') 换成 date_trunc('day')）。
    PROCEDURE build_payment_incremental(p_run_id varchar2,
                                        o_rows OUT integer, o_months OUT integer) IS
        v_id_from bigint; v_id_to bigint;
        v_ts_from timestamptz; v_ts_to timestamptz;
        v_rows integer; v_status varchar2(16);
        v_m timestamp;
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_payment_incremental');
        o_rows := 0; o_months := 0;

        dw.pkg_etl_core.plan_increment('payment', v_id_from, v_id_to, v_ts_from, v_ts_to);

        FOR rec IN (SELECT DISTINCT date_trunc('month', p.payment_date AT TIME ZONE 'UTC') AS m
                      FROM public.payment p
                     WHERE (p.payment_id > v_id_from AND p.payment_id <= v_id_to)
                        OR (p.payment_date >= v_ts_from AND p.payment_date < v_ts_to)
                     ORDER BY 1) LOOP
            v_m := rec.m;
            build_dwd_fact_payment(v_m::date, (v_m + interval '1 month')::date,
                                   p_run_id, v_rows, v_status);
            o_rows   := o_rows + v_rows;
            o_months := o_months + 1;
        END LOOP;

        dw.pkg_etl_core.commit_increment('payment', v_id_to, v_ts_to, p_run_id);

        dw.pkg_etl_core.log_end(p_run_id, 'build_payment_incremental', 'OK', o_rows, NULL, NULL);
        RAISE NOTICE 'build_payment_incremental: % month(s), % row(s)', o_months, o_rows;
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_payment_incremental', 'FAILED', 0,
                                SQLSTATE, SQLERRM);
        RAISE;
    END;

    -- rental 有 last_update（BEFORE UPDATE 触发器维护），故走 TS 单轨。
    -- 受影响月份按 rental_date 归属：归还日期被更新时 last_update 变化，
    -- 但 rental_date 所在月不变，正确的那个月会被重建。
    PROCEDURE build_rental_incremental(p_run_id varchar2,
                                       o_rows OUT integer, o_months OUT integer) IS
        v_id_from bigint; v_id_to bigint;
        v_ts_from timestamptz; v_ts_to timestamptz;
        v_rows integer; v_status varchar2(16);
        v_m timestamp;
    BEGIN
        dw.pkg_etl_core.log_start(p_run_id, 'build_rental_incremental');
        o_rows := 0; o_months := 0;

        dw.pkg_etl_core.plan_increment('rental', v_id_from, v_id_to, v_ts_from, v_ts_to);

        FOR rec IN (SELECT DISTINCT date_trunc('month', r.rental_date AT TIME ZONE 'UTC') AS m
                      FROM public.rental r
                     WHERE r.last_update >= v_ts_from AND r.last_update < v_ts_to
                     ORDER BY 1) LOOP
            v_m := rec.m;
            build_dwd_fact_rental(v_m::date, (v_m + interval '1 month')::date,
                                  p_run_id, v_rows, v_status);
            o_rows   := o_rows + v_rows;
            o_months := o_months + 1;
        END LOOP;

        dw.pkg_etl_core.commit_increment('rental', NULL, v_ts_to, p_run_id);

        dw.pkg_etl_core.log_end(p_run_id, 'build_rental_incremental', 'OK', o_rows, NULL, NULL);
        RAISE NOTICE 'build_rental_incremental: % month(s), % row(s)', o_months, o_rows;
    EXCEPTION WHEN OTHERS THEN
        dw.pkg_etl_core.log_end(p_run_id, 'build_rental_incremental', 'FAILED', 0,
                                SQLSTATE, SQLERRM);
        RAISE;
    END;

    -- 生成"可作为顶层语句提交"的 DELETE+INSERT 文本，供 QUEUE 模式（方案 §5.3 的
    -- O1）使用。存在理由：openGauss 官方明确"存储过程和函数内的查询不支持并行执行
    -- (SMP)"，企业版亦然。若由外部 worker 执行 `CALL build_dwd_fact_payment(...)`，
    -- SQL 仍在过程内运行、拿不到 SMP —— 所以 QUEUE 模式必须投递**裸 SQL**。
    --
    -- ⚠️ 已知维护成本：本函数与 build_dwd_fact_payment 的静态 SQL 是两处定义，
    -- 存在漂移风险。**防漂移手段是强制的等价性断言**
    -- （sqls/dw/tests/qa-phase2-orch.sql 的 mode-equivalence 用例：两种模式跑同一
    -- 期间后双向 EXCEPT 必须为 0）。修改任一处都必须同步另一处并重跑该用例。
    --
    -- analysis_cutoff 用标量子查询而非生成时内联字面量，保证与静态版（读入变量）
    -- 的求值语义一致：优化器会作为 InitPlan 只求值一次。
    FUNCTION gen_payment_sql(p_date_from date, p_date_to date, p_run_id varchar2) RETURN text IS
        v_from text := quote_literal(to_char(p_date_from, 'YYYY-MM-DD'));
        v_to   text := quote_literal(to_char(p_date_to,   'YYYY-MM-DD'));
        v_cut  text := '(SELECT analysis_cutoff FROM dw.v_analysis_cutoff)';
    BEGIN
        RETURN
        'DELETE FROM dw.dwd_fact_payment WHERE stat_date >= ' || v_from ||
        ' AND stat_date < ' || v_to || '; ' ||
        'INSERT INTO dw.dwd_fact_payment(' ||
        'stat_date, payment_ts, payment_id, rental_id, customer_id, staff_id, ' ||
        'store_id, store_status, film_id, category_id, category_name, ' ||
        'store_city, store_country, amount, is_within_cutoff, multi_category, ' ||
        'dq_flag, run_id) ' ||
        'SELECT date_trunc(''day'', p.payment_date AT TIME ZONE ''UTC''), ' ||
        'p.payment_date, p.payment_id, p.rental_id, p.customer_id, p.staff_id, ' ||
        'i.store_id, ds.store_status, i.film_id, df.category_id, df.category_name, ' ||
        'ds.city, ds.country, p.amount::numeric(18,2), ' ||
        'p.payment_date <= ' || v_cut || ', ' ||
        'COALESCE(df.multi_category, false), ' ||
        '(ds.store_id IS NULL) OR (ds.store_status IN (''EXCLUDED'',''UNCLASSIFIED'')) ' ||
        'OR (ds.mgr_is_orphan) OR (ds.staff_cnt = 0) OR (df.film_id IS NULL) ' ||
        'OR (p.payment_date > ' || v_cut || '), ' ||
        quote_literal(p_run_id) || ' ' ||
        'FROM public.payment p ' ||
        'LEFT JOIN public.rental r    ON r.rental_id = p.rental_id ' ||
        'LEFT JOIN public.inventory i ON i.inventory_id = r.inventory_id ' ||
        'LEFT JOIN dw.dim_store ds    ON ds.store_id = i.store_id ' ||
        'LEFT JOIN dw.dim_film df     ON df.film_id = i.film_id ' ||
        'WHERE p.payment_date >= ' || v_from || ' AND p.payment_date < ' || v_to || ';';
    END;

    FUNCTION gen_rental_sql(p_date_from date, p_date_to date, p_run_id varchar2) RETURN text IS
        v_from text := quote_literal(to_char(p_date_from, 'YYYY-MM-DD'));
        v_to   text := quote_literal(to_char(p_date_to,   'YYYY-MM-DD'));
        v_cut  text := '(SELECT analysis_cutoff FROM dw.v_analysis_cutoff)';
    BEGIN
        RETURN
        'DELETE FROM dw.dwd_fact_rental WHERE stat_date >= ' || v_from ||
        ' AND stat_date < ' || v_to || '; ' ||
        'INSERT INTO dw.dwd_fact_rental(' ||
        'stat_date, rental_ts, rental_id, return_ts, customer_id, staff_id, ' ||
        'inventory_id, film_id, store_id, store_status, category_id, category_name, ' ||
        'rental_duration, is_returned, is_overdue, overdue_days, ' ||
        'is_within_cutoff, dq_flag, run_id) ' ||
        'SELECT date_trunc(''day'', r.rental_date AT TIME ZONE ''UTC''), ' ||
        'r.rental_date, r.rental_id, r.return_date, r.customer_id, r.staff_id, ' ||
        'r.inventory_id, i.film_id, i.store_id, ds.store_status, ' ||
        'df.category_id, df.category_name, f.rental_duration, ' ||
        'r.return_date IS NOT NULL, ' ||
        'r.return_date IS NULL AND LEAST(' || v_cut || ', now()) > r.rental_date ' ||
        '+ (f.rental_duration * interval ''1 day''), ' ||
        'CASE WHEN r.return_date IS NULL THEN GREATEST(0, ' ||
        'floor(EXTRACT(EPOCH FROM (LEAST(' || v_cut || ', now()) - r.rental_date)) / 86400)::integer ' ||
        '- COALESCE(f.rental_duration, 0)) ELSE NULL END, ' ||
        'r.rental_date <= ' || v_cut || ', ' ||
        '(ds.store_id IS NULL) OR (ds.store_status IN (''EXCLUDED'',''UNCLASSIFIED'')) ' ||
        'OR (df.film_id IS NULL) OR (r.rental_date > ' || v_cut || '), ' ||
        quote_literal(p_run_id) || ' ' ||
        'FROM public.rental r ' ||
        'LEFT JOIN public.inventory i ON i.inventory_id = r.inventory_id ' ||
        'LEFT JOIN public.film f      ON f.film_id = i.film_id ' ||
        'LEFT JOIN dw.dim_store ds    ON ds.store_id = i.store_id ' ||
        'LEFT JOIN dw.dim_film df     ON df.film_id = i.film_id ' ||
        'WHERE r.rental_date >= ' || v_from || ' AND r.rental_date < ' || v_to || ';';
    END;

END pkg_dwd;
/
