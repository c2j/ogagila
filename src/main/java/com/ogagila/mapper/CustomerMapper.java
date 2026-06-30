package com.ogagila.mapper;

import com.ogagila.entity.Customer;
import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Map;

public interface CustomerMapper {

    List<Customer> selectAll(@Param("offset") Integer offset, @Param("limit") Integer limit);

    int countAll();

    Customer selectById(@Param("customerId") Integer customerId);

    Customer selectWithAddress(@Param("customerId") Integer customerId);

    int insert(Customer customer);

    int update(Customer customer);

    int delete(@Param("customerId") Integer customerId);

    List<Map<String, Object>> selectHighValueCustomers(@Param("minAmount") Double minAmount);

    List<Customer> selectByStoreHierarchical(@Param("storeId") Integer storeId);
}
