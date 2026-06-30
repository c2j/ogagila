package com.ogagila.mapper;

import com.ogagila.entity.FilmCategory;
import com.ogagila.entity.FilmCategoryId;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface FilmCategoryMapper {

    List<FilmCategory> selectByFilm(@Param("filmId") Integer filmId);

    List<FilmCategory> selectByCategory(@Param("categoryId") Integer categoryId);

    int insert(FilmCategory filmCategory);

    int delete(FilmCategoryId id);
}
