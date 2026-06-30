package com.ogagila.mapper;

import com.ogagila.entity.Store;
import org.apache.ibatis.annotations.MapKey;
import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Map;

public interface StoreMapper {

    List<Store> selectAll(@Param("offset") Integer offset, @Param("limit") Integer limit);

    int countAll();

    Store selectById(@Param("storeId") Integer storeId);

    Store selectWithManager(@Param("storeId") Integer storeId);

    List<Map<String, Object>> selectSalesReport(@Param("storeId") Integer storeId);
}
