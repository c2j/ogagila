package com.ogagila.mapper;

import org.apache.ibatis.annotations.Param;

import java.util.Map;

public interface ProcedureMapper {

    Map<String, Object> filmInStock(@Param("filmId") Integer filmId,
                                     @Param("storeId") Integer storeId);

    Map<String, Object> getCustomerBalance(@Param("customerId") Integer customerId);

    Map<String, Object> rewardsReport(@Param("minPurchases") Integer minPurchases,
                                       @Param("minAmount") Double minAmount);

    Map<String, Object> inventoryInStock(@Param("inventoryId") Integer inventoryId);
}
