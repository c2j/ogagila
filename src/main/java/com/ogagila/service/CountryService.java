package com.ogagila.service;

import com.ogagila.entity.Country;
import com.ogagila.mapper.CountryMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class CountryService {

    private final CountryMapper countryMapper;

    public CountryService(CountryMapper countryMapper) {
        this.countryMapper = countryMapper;
    }

    @Transactional(readOnly = true)
    public List<Country> getAll() {
        return countryMapper.selectAll();
    }

    @Transactional(readOnly = true)
    public Country getById(Integer countryId) {
        return countryMapper.selectById(countryId);
    }

    public Country create(Country country) {
        countryMapper.insert(country);
        return country;
    }

    public Country update(Country country) {
        countryMapper.update(country);
        return country;
    }
}
