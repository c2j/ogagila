package com.ogagila.controller.api.dto;

import com.ogagila.entity.Actor;
import com.ogagila.entity.Category;
import com.ogagila.entity.Film;

import java.util.List;

/**
 * Combines Film entity with its associated actors and categories.
 */
public class FilmDetailDTO {

    private Film film;
    private List<Actor> actors;
    private List<Category> categories;

    public FilmDetailDTO() {
    }

    public FilmDetailDTO(Film film, List<Actor> actors, List<Category> categories) {
        this.film = film;
        this.actors = actors;
        this.categories = categories;
    }

    public Film getFilm() {
        return film;
    }

    public void setFilm(Film film) {
        this.film = film;
    }

    public List<Actor> getActors() {
        return actors;
    }

    public void setActors(List<Actor> actors) {
        this.actors = actors;
    }

    public List<Category> getCategories() {
        return categories;
    }

    public void setCategories(List<Category> categories) {
        this.categories = categories;
    }
}
