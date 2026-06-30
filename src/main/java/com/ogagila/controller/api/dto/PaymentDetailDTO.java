package com.ogagila.controller.api.dto;

import com.ogagila.entity.Payment;

/**
 * Combines Payment with customer name for display purposes.
 */
public class PaymentDetailDTO {

    private Payment payment;
    private String customerName;

    public PaymentDetailDTO() {
    }

    public PaymentDetailDTO(Payment payment, String customerName) {
        this.payment = payment;
        this.customerName = customerName;
    }

    public Payment getPayment() {
        return payment;
    }

    public void setPayment(Payment payment) {
        this.payment = payment;
    }

    public String getCustomerName() {
        return customerName;
    }

    public void setCustomerName(String customerName) {
        this.customerName = customerName;
    }
}
