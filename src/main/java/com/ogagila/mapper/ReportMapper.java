package com.ogagila.mapper;

import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Map;

public interface ReportMapper {

    Map<String, Object> selectDashboardStats();

    List<Map<String, Object>> selectSalesByCategory();

    List<Map<String, Object>> selectSalesByStore();

    List<Map<String, Object>> selectTopFilms(@Param("limit") Integer limit);

    List<Map<String, Object>> selectTopActors(@Param("limit") Integer limit);

    List<Map<String, Object>> selectMonthlyRevenue(@Param("year") Integer year);

    List<Map<String, Object>> selectCustomerActivity(@Param("limit") Integer limit);
}
