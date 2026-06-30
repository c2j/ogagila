package com.ogagila.entity;

import java.io.Serializable;
import java.util.Objects;

public class FilmCategoryId implements Serializable {

    private Integer filmId;
    private Integer categoryId;

    public FilmCategoryId() {
    }

    public FilmCategoryId(Integer filmId, Integer categoryId) {
        this.filmId = filmId;
        this.categoryId = categoryId;
    }

    public Integer getFilmId() {
        return filmId;
    }

    public void setFilmId(Integer filmId) {
        this.filmId = filmId;
    }

    public Integer getCategoryId() {
        return categoryId;
    }

    public void setCategoryId(Integer categoryId) {
        this.categoryId = categoryId;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        FilmCategoryId that = (FilmCategoryId) o;
        return Objects.equals(filmId, that.filmId) &&
                Objects.equals(categoryId, that.categoryId);
    }

    @Override
    public int hashCode() {
        return Objects.hash(filmId, categoryId);
    }

    @Override
    public String toString() {
        return "FilmCategoryId{" +
                "filmId=" + filmId +
                ", categoryId=" + categoryId +
                '}';
    }
}
