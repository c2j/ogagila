package com.ogagila.service;

import com.ogagila.entity.City;
import com.ogagila.mapper.CityMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class CityService {

    private final CityMapper cityMapper;

    public CityService(CityMapper cityMapper) {
        this.cityMapper = cityMapper;
    }

    @Transactional(readOnly = true)
    public List<City> getAll() {
        return cityMapper.selectAll();
    }

    @Transactional(readOnly = true)
    public List<City> getByCountry(Integer countryId) {
        return cityMapper.selectByCountry(countryId);
    }

    public City create(City city) {
        cityMapper.insert(city);
        return city;
    }

    public City update(City city) {
        cityMapper.update(city);
        return city;
    }
}
