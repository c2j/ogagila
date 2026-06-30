package com.ogagila.mapper;

import com.ogagila.entity.Address;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface AddressMapper {

    List<Address> selectAll();

    Address selectById(@Param("addressId") Integer addressId);

    List<Address> selectByCity(@Param("cityId") Integer cityId);

    int insert(Address address);

    int update(Address address);
}
