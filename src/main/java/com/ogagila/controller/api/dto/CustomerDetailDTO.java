package com.ogagila.controller.api.dto;

import com.ogagila.entity.Address;
import com.ogagila.entity.City;
import com.ogagila.entity.Country;
import com.ogagila.entity.Customer;

/**
 * Combines Customer entity with its full address hierarchy.
 */
public class CustomerDetailDTO {

    private Customer customer;
    private Address address;
    private City city;
    private Country country;

    public CustomerDetailDTO() {
    }

    public CustomerDetailDTO(Customer customer, Address address, City city, Country country) {
        this.customer = customer;
        this.address = address;
        this.city = city;
        this.country = country;
    }

    public Customer getCustomer() {
        return customer;
    }

    public void setCustomer(Customer customer) {
        this.customer = customer;
    }

    public Address getAddress() {
        return address;
    }

    public void setAddress(Address address) {
        this.address = address;
    }

    public City getCity() {
        return city;
    }

    public void setCity(City city) {
        this.city = city;
    }

    public Country getCountry() {
        return country;
    }

    public void setCountry(Country country) {
        this.country = country;
    }
}
