package com.ogagila.service;

import com.ogagila.controller.api.dto.CustomerDetailDTO;
import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.entity.Address;
import com.ogagila.entity.City;
import com.ogagila.entity.Country;
import com.ogagila.entity.Customer;
import com.ogagila.mapper.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

@Service
@Transactional
public class CustomerService {

    private final CustomerMapper customerMapper;
    private final AddressMapper addressMapper;
    private final CityMapper cityMapper;
    private final CountryMapper countryMapper;

    public CustomerService(CustomerMapper customerMapper, AddressMapper addressMapper,
                           CityMapper cityMapper, CountryMapper countryMapper) {
        this.customerMapper = customerMapper;
        this.addressMapper = addressMapper;
        this.cityMapper = cityMapper;
        this.countryMapper = countryMapper;
    }

    @Transactional(readOnly = true)
    public PageResult<Customer> getAll(int page, int size) {
        int offset = (page - 1) * size;
        List<Customer> customers = customerMapper.selectAll(offset, size);
        long total = customerMapper.countAll();
        return new PageResult<>(customers, total, page, size);
    }

    @Transactional(readOnly = true)
    public Customer getById(Integer customerId) {
        return customerMapper.selectById(customerId);
    }

    @Transactional(readOnly = true)
    public CustomerDetailDTO getDetail(Integer customerId) {
        Customer customer = customerMapper.selectById(customerId);
        if (customer == null) {
            return null;
        }
        Address address = addressMapper.selectById(customer.getAddressId());
        City city = null;
        Country country = null;
        if (address != null) {
            city = cityMapper.selectById(address.getCityId());
            if (city != null) {
                country = countryMapper.selectById(city.getCountryId());
            }
        }
        return new CustomerDetailDTO(customer, address, city, country);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> getHighValueCustomers(Double minAmount) {
        double min = (minAmount != null) ? minAmount : 100.0;
        return customerMapper.selectHighValueCustomers(min);
    }

    @Transactional(readOnly = true)
    public List<Customer> getByStoreHierarchical(Integer storeId) {
        return customerMapper.selectByStoreHierarchical(storeId);
    }

    public Customer create(Customer customer) {
        customerMapper.insert(customer);
        return customer;
    }

    public Customer update(Customer customer) {
        customerMapper.update(customer);
        return customer;
    }

    public void delete(Integer customerId) {
        customerMapper.delete(customerId);
    }
}
