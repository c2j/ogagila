package com.ogagila.service;

import com.ogagila.controller.api.dto.FilmDetailDTO;
import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.entity.Actor;
import com.ogagila.entity.Category;
import com.ogagila.entity.Film;
import com.ogagila.mapper.*;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@Transactional
public class FilmService {

    private final FilmMapper filmMapper;
    private final FilmActorMapper filmActorMapper;
    private final FilmCategoryMapper filmCategoryMapper;
    private final ActorMapper actorMapper;
    private final CategoryMapper categoryMapper;

    public FilmService(FilmMapper filmMapper, FilmActorMapper filmActorMapper,
                       FilmCategoryMapper filmCategoryMapper, ActorMapper actorMapper,
                       CategoryMapper categoryMapper) {
        this.filmMapper = filmMapper;
        this.filmActorMapper = filmActorMapper;
        this.filmCategoryMapper = filmCategoryMapper;
        this.actorMapper = actorMapper;
        this.categoryMapper = categoryMapper;
    }

    @Transactional(readOnly = true)
    public PageResult<Film> getAll(int page, int size) {
        int offset = (page - 1) * size;
        List<Film> films = filmMapper.selectAll(offset, size);
        long total = filmMapper.countAll();
        return new PageResult<>(films, total, page, size);
    }

    @Transactional(readOnly = true)
    public Film getById(Integer filmId) {
        return filmMapper.selectById(filmId);
    }

    @Transactional(readOnly = true)
    public PageResult<Film> searchByTitle(String keyword, int page, int size) {
        int offset = (page - 1) * size;
        String searchKeyword = keyword.trim();
        List<Film> films = filmMapper.selectByTitle(searchKeyword, offset, size);
        long total = filmMapper.countByTitle(searchKeyword);
        return new PageResult<>(films, total, page, size);
    }

    @Transactional(readOnly = true)
    public FilmDetailDTO getDetail(Integer filmId) {
        Film film = filmMapper.selectById(filmId);
        if (film == null) {
            return null;
        }
        List<Actor> actors = filmActorMapper.selectByFilm(filmId).stream()
                .map(fa -> actorMapper.selectById(fa.getActorId()))
                .collect(Collectors.toList());
        List<Category> categories = filmCategoryMapper.selectByFilm(filmId).stream()
                .map(fc -> categoryMapper.selectById(fc.getCategoryId()))
                .collect(Collectors.toList());
        return new FilmDetailDTO(film, actors, categories);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> getOverdueFilms() {
        return filmMapper.selectOverdueFilms();
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> getTopRented(Integer topN) {
        int limit = (topN != null && topN > 0) ? topN : 10;
        return filmMapper.selectTopRented(limit);
    }

    public Film create(Film film) {
        filmMapper.insert(film);
        return film;
    }

    public Film update(Film film) {
        filmMapper.update(film);
        return film;
    }

    public void delete(Integer filmId) {
        filmMapper.delete(filmId);
    }
}
