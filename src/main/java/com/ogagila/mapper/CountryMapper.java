package com.ogagila.mapper;

import com.ogagila.entity.Country;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface CountryMapper {

    List<Country> selectAll();

    Country selectById(@Param("countryId") Integer countryId);

    int insert(Country country);

    int update(Country country);
}
