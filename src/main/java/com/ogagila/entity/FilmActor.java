package com.ogagila.entity;

import java.time.OffsetDateTime;

public class FilmActor {

    private FilmActorId id;
    private Integer actorId;
    private Integer filmId;
    private OffsetDateTime lastUpdate;

    public FilmActor() {
    }

    public FilmActor(Integer actorId, Integer filmId, OffsetDateTime lastUpdate) {
        this.actorId = actorId;
        this.filmId = filmId;
        this.lastUpdate = lastUpdate;
        this.id = new FilmActorId(actorId, filmId);
    }

    public FilmActorId getId() {
        return id;
    }

    public void setId(FilmActorId id) {
        this.id = id;
        if (id != null) {
            this.actorId = id.getActorId();
            this.filmId = id.getFilmId();
        }
    }

    public Integer getActorId() {
        return actorId;
    }

    public void setActorId(Integer actorId) {
        this.actorId = actorId;
        if (this.id == null) {
            this.id = new FilmActorId();
        }
        this.id.setActorId(actorId);
    }

    public Integer getFilmId() {
        return filmId;
    }

    public void setFilmId(Integer filmId) {
        this.filmId = filmId;
        if (this.id == null) {
            this.id = new FilmActorId();
        }
        this.id.setFilmId(filmId);
    }

    public OffsetDateTime getLastUpdate() {
        return lastUpdate;
    }

    public void setLastUpdate(OffsetDateTime lastUpdate) {
        this.lastUpdate = lastUpdate;
    }

    @Override
    public String toString() {
        return "FilmActor{" +
                "actorId=" + actorId +
                ", filmId=" + filmId +
                ", lastUpdate=" + lastUpdate +
                '}';
    }
}
