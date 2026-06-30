package com.ogagila.service;

import com.ogagila.entity.Address;
import com.ogagila.mapper.AddressMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class AddressService {

    private final AddressMapper addressMapper;

    public AddressService(AddressMapper addressMapper) {
        this.addressMapper = addressMapper;
    }

    @Transactional(readOnly = true)
    public List<Address> getAll() {
        return addressMapper.selectAll();
    }

    @Transactional(readOnly = true)
    public List<Address> getByCity(Integer cityId) {
        return addressMapper.selectByCity(cityId);
    }

    public Address create(Address address) {
        addressMapper.insert(address);
        return address;
    }

    public Address update(Address address) {
        addressMapper.update(address);
        return address;
    }
}
