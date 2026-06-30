package com.ogagila.mapper;

import com.ogagila.entity.FilmActor;
import com.ogagila.entity.FilmActorId;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface FilmActorMapper {

    List<FilmActor> selectByFilm(@Param("filmId") Integer filmId);

    List<FilmActor> selectByActor(@Param("actorId") Integer actorId);

    int insert(FilmActor filmActor);

    int delete(FilmActorId id);
}
