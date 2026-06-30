package com.ogagila.service;

import com.ogagila.controller.api.dto.DashboardDTO;
import com.ogagila.mapper.ReportMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@Service
@Transactional(readOnly = true)
public class ReportService {

    private final ReportMapper reportMapper;

    public ReportService(ReportMapper reportMapper) {
        this.reportMapper = reportMapper;
    }

    public DashboardDTO getDashboard() {
        Map<String, Object> stats = reportMapper.selectDashboardStats();
        List<Map<String, Object>> topFilms = reportMapper.selectTopFilms(5);
        List<Map<String, Object>> monthlyRevenue = reportMapper.selectMonthlyRevenue(java.time.LocalDate.now().getYear());

        DashboardDTO dto = new DashboardDTO();
        if (stats != null) {
            dto.setFilmCount(toLong(stats.get("film_count")));
            dto.setCustomerCount(toLong(stats.get("customer_count")));
            dto.setRentalCount(toLong(stats.get("rental_count")));
            dto.setTotalRevenue(toBigDecimal(stats.get("total_revenue")));
            dto.setOverdueCount(toLong(stats.get("overdue_count")));
            dto.setActorCount(toLong(stats.get("actor_count")));
            dto.setInventoryCount(toLong(stats.get("inventory_count")));
            dto.setStoreCount(toLong(stats.get("store_count")));
        }
        dto.setTopFilms(topFilms);
        dto.setMonthlyRevenue(monthlyRevenue);
        return dto;
    }

    public List<Map<String, Object>> getSalesByCategory() {
        return reportMapper.selectSalesByCategory();
    }

    public List<Map<String, Object>> getSalesByStore() {
        return reportMapper.selectSalesByStore();
    }

    public List<Map<String, Object>> getTopFilms(Integer limit) {
        int topN = (limit != null && limit > 0) ? limit : 10;
        return reportMapper.selectTopFilms(topN);
    }

    public List<Map<String, Object>> getTopActors(Integer limit) {
        int topN = (limit != null && limit > 0) ? limit : 10;
        return reportMapper.selectTopActors(topN);
    }

    public List<Map<String, Object>> getMonthlyRevenue(Integer year) {
        int y = (year != null) ? year : java.time.LocalDate.now().getYear();
        return reportMapper.selectMonthlyRevenue(y);
    }

    public List<Map<String, Object>> getCustomerActivity(Integer limit) {
        int topN = (limit != null && limit > 0) ? limit : 20;
        return reportMapper.selectCustomerActivity(topN);
    }

    private long toLong(Object value) {
        if (value instanceof Number) {
            return ((Number) value).longValue();
        }
        return 0L;
    }

    private BigDecimal toBigDecimal(Object value) {
        if (value instanceof Number) {
            return BigDecimal.valueOf(((Number) value).doubleValue());
        }
        return BigDecimal.ZERO;
    }
}
