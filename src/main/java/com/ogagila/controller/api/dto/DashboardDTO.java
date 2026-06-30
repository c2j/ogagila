package com.ogagila.controller.api.dto;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

/**
 * Aggregated dashboard statistics for the main overview page.
 */
public class DashboardDTO {

    private long filmCount;
    private long customerCount;
    private long rentalCount;
    private BigDecimal totalRevenue;
    private long overdueCount;
    private long actorCount;
    private long inventoryCount;
    private long storeCount;
    private List<Map<String, Object>> topFilms;
    private List<Map<String, Object>> monthlyRevenue;

    public DashboardDTO() {
    }

    public long getFilmCount() {
        return filmCount;
    }

    public void setFilmCount(long filmCount) {
        this.filmCount = filmCount;
    }

    public long getCustomerCount() {
        return customerCount;
    }

    public void setCustomerCount(long customerCount) {
        this.customerCount = customerCount;
    }

    public long getRentalCount() {
        return rentalCount;
    }

    public void setRentalCount(long rentalCount) {
        this.rentalCount = rentalCount;
    }

    public BigDecimal getTotalRevenue() {
        return totalRevenue;
    }

    public void setTotalRevenue(BigDecimal totalRevenue) {
        this.totalRevenue = totalRevenue;
    }

    public long getOverdueCount() {
        return overdueCount;
    }

    public void setOverdueCount(long overdueCount) {
        this.overdueCount = overdueCount;
    }

    public long getActorCount() {
        return actorCount;
    }

    public void setActorCount(long actorCount) {
        this.actorCount = actorCount;
    }

    public long getInventoryCount() {
        return inventoryCount;
    }

    public void setInventoryCount(long inventoryCount) {
        this.inventoryCount = inventoryCount;
    }

    public long getStoreCount() {
        return storeCount;
    }

    public void setStoreCount(long storeCount) {
        this.storeCount = storeCount;
    }

    public List<Map<String, Object>> getTopFilms() {
        return topFilms;
    }

    public void setTopFilms(List<Map<String, Object>> topFilms) {
        this.topFilms = topFilms;
    }

    public List<Map<String, Object>> getMonthlyRevenue() {
        return monthlyRevenue;
    }

    public void setMonthlyRevenue(List<Map<String, Object>> monthlyRevenue) {
        this.monthlyRevenue = monthlyRevenue;
    }
}
