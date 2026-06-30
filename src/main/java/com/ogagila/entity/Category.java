package com.ogagila.entity;

import java.time.OffsetDateTime;

/**
 * Entity mapping for category table.
 * Represents a film category (e.g., Action, Comedy, Drama).
 */
public class Category {

    private Integer categoryId;
    private String name;
    private OffsetDateTime lastUpdate;

    public Category() {
    }

    public Category(Integer categoryId, String name, OffsetDateTime lastUpdate) {
        this.categoryId = categoryId;
        this.name = name;
        this.lastUpdate = lastUpdate;
    }

    public Integer getCategoryId() {
        return categoryId;
    }

    public void setCategoryId(Integer categoryId) {
        this.categoryId = categoryId;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public OffsetDateTime getLastUpdate() {
        return lastUpdate;
    }

    public void setLastUpdate(OffsetDateTime lastUpdate) {
        this.lastUpdate = lastUpdate;
    }

    @Override
    public String toString() {
        return "Category{" +
                "categoryId=" + categoryId +
                ", name='" + name + '\'' +
                ", lastUpdate=" + lastUpdate +
                '}';
    }
}
