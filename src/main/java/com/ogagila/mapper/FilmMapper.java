package com.ogagila.mapper;

import com.ogagila.entity.Film;
import org.apache.ibatis.annotations.Param;

import java.util.List;
import java.util.Map;

public interface FilmMapper {

    List<Film> selectAll(@Param("offset") Integer offset, @Param("limit") Integer limit);

    int countAll();

    Film selectById(@Param("filmId") Integer filmId);

    List<Film> selectByTitle(@Param("keyword") String keyword,
                             @Param("offset") Integer offset,
                             @Param("limit") Integer limit);

    int countByTitle(@Param("keyword") String keyword);

    Film selectWithActors(@Param("filmId") Integer filmId);

    Film selectWithCategories(@Param("filmId") Integer filmId);

    int insert(Film film);

    int update(Film film);

    int delete(@Param("filmId") Integer filmId);

    List<Map<String, Object>> selectOverdueFilms();

    List<Map<String, Object>> selectTopRented(@Param("topN") Integer topN);
}
