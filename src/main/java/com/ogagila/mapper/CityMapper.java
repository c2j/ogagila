package com.ogagila.mapper;

import com.ogagila.entity.City;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface CityMapper {

    List<City> selectAll();

    City selectById(@Param("cityId") Integer cityId);

    List<City> selectByCountry(@Param("countryId") Integer countryId);

    int insert(City city);

    int update(City city);
}
