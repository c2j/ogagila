package com.ogagila.entity;

import java.time.OffsetDateTime;

public class FilmCategory {

    private FilmCategoryId id;
    private Integer filmId;
    private Integer categoryId;
    private OffsetDateTime lastUpdate;

    public FilmCategory() {
    }

    public FilmCategory(Integer filmId, Integer categoryId, OffsetDateTime lastUpdate) {
        this.filmId = filmId;
        this.categoryId = categoryId;
        this.lastUpdate = lastUpdate;
        this.id = new FilmCategoryId(filmId, categoryId);
    }

    public FilmCategoryId getId() {
        return id;
    }

    public void setId(FilmCategoryId id) {
        this.id = id;
        if (id != null) {
            this.filmId = id.getFilmId();
            this.categoryId = id.getCategoryId();
        }
    }

    public Integer getFilmId() {
        return filmId;
    }

    public void setFilmId(Integer filmId) {
        this.filmId = filmId;
        if (this.id == null) {
            this.id = new FilmCategoryId();
        }
        this.id.setFilmId(filmId);
    }

    public Integer getCategoryId() {
        return categoryId;
    }

    public void setCategoryId(Integer categoryId) {
        this.categoryId = categoryId;
        if (this.id == null) {
            this.id = new FilmCategoryId();
        }
        this.id.setCategoryId(categoryId);
    }

    public OffsetDateTime getLastUpdate() {
        return lastUpdate;
    }

    public void setLastUpdate(OffsetDateTime lastUpdate) {
        this.lastUpdate = lastUpdate;
    }

    @Override
    public String toString() {
        return "FilmCategory{" +
                "filmId=" + filmId +
                ", categoryId=" + categoryId +
                ", lastUpdate=" + lastUpdate +
                '}';
    }
}
