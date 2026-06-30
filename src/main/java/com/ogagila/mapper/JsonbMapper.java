package com.ogagila.mapper;

import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Map;

public interface JsonbMapper {

    List<Map<String, Object>> selectPackagesApt();

    List<Map<String, Object>> selectPackagesYum();

    List<Map<String, Object>> searchPackages(@Param("keyword") String keyword);

    Map<String, Object> selectPackageById(@Param("id") Integer id);
}
