package com.ogagila.entity;

import java.time.OffsetDateTime;

public class Rental {

    private Integer rentalId;
    private OffsetDateTime rentalDate;
    private Integer inventoryId;
    private Integer customerId;
    private OffsetDateTime returnDate;
    private Integer staffId;
    private OffsetDateTime lastUpdate;

    public Rental() {
    }

    public Rental(Integer rentalId, OffsetDateTime rentalDate, Integer inventoryId,
                  Integer customerId, OffsetDateTime returnDate, Integer staffId,
                  OffsetDateTime lastUpdate) {
        this.rentalId = rentalId;
        this.rentalDate = rentalDate;
        this.inventoryId = inventoryId;
        this.customerId = customerId;
        this.returnDate = returnDate;
        this.staffId = staffId;
        this.lastUpdate = lastUpdate;
    }

    public Integer getRentalId() {
        return rentalId;
    }

    public void setRentalId(Integer rentalId) {
        this.rentalId = rentalId;
    }

    public OffsetDateTime getRentalDate() {
        return rentalDate;
    }

    public void setRentalDate(OffsetDateTime rentalDate) {
        this.rentalDate = rentalDate;
    }

    public Integer getInventoryId() {
        return inventoryId;
    }

    public void setInventoryId(Integer inventoryId) {
        this.inventoryId = inventoryId;
    }

    public Integer getCustomerId() {
        return customerId;
    }

    public void setCustomerId(Integer customerId) {
        this.customerId = customerId;
    }

    public OffsetDateTime getReturnDate() {
        return returnDate;
    }

    public void setReturnDate(OffsetDateTime returnDate) {
        this.returnDate = returnDate;
    }

    public Integer getStaffId() {
        return staffId;
    }

    public void setStaffId(Integer staffId) {
        this.staffId = staffId;
    }

    public OffsetDateTime getLastUpdate() {
        return lastUpdate;
    }

    public void setLastUpdate(OffsetDateTime lastUpdate) {
        this.lastUpdate = lastUpdate;
    }

    @Override
    public String toString() {
        return "Rental{" +
                "rentalId=" + rentalId +
                ", rentalDate=" + rentalDate +
                ", inventoryId=" + inventoryId +
                ", customerId=" + customerId +
                ", returnDate=" + returnDate +
                ", staffId=" + staffId +
                ", lastUpdate=" + lastUpdate +
                '}';
    }
}
