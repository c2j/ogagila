package com.ogagila.controller.api.dto;

import com.ogagila.entity.Rental;

/**
 * Combines Rental with film title and customer name for display purposes.
 */
public class RentalDetailDTO {

    private Rental rental;
    private String filmTitle;
    private String customerName;

    public RentalDetailDTO() {
    }

    public RentalDetailDTO(Rental rental, String filmTitle, String customerName) {
        this.rental = rental;
        this.filmTitle = filmTitle;
        this.customerName = customerName;
    }

    public Rental getRental() {
        return rental;
    }

    public void setRental(Rental rental) {
        this.rental = rental;
    }

    public String getFilmTitle() {
        return filmTitle;
    }

    public void setFilmTitle(String filmTitle) {
        this.filmTitle = filmTitle;
    }

    public String getCustomerName() {
        return customerName;
    }

    public void setCustomerName(String customerName) {
        this.customerName = customerName;
    }
}
