package com.ogagila.controller.api;

import com.ogagila.controller.api.dto.FilmDetailDTO;
import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.entity.Film;
import com.ogagila.service.FilmService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/films")
@CrossOrigin(origins = {"http://localhost:5173", "http://localhost:8080"})
public class FilmApiController {

    private final FilmService filmService;

    public FilmApiController(FilmService filmService) {
        this.filmService = filmService;
    }

    @GetMapping
    public ResponseEntity<PageResult<Film>> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int size) {
        PageResult<Film> result = filmService.getAll(page, size);
        return ResponseEntity.ok(result);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Film> getById(@PathVariable("id") Integer id) {
        Film film = filmService.getById(id);
        if (film == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(film);
    }

    @GetMapping("/detail/{id}")
    public ResponseEntity<FilmDetailDTO> getDetail(@PathVariable("id") Integer id) {
        FilmDetailDTO detail = filmService.getDetail(id);
        if (detail == null || detail.getFilm() == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(detail);
    }

    @GetMapping("/search")
    public ResponseEntity<PageResult<Film>> search(
            @RequestParam String keyword,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int size) {
        if (keyword == null || keyword.trim().isEmpty()) {
            return ResponseEntity.badRequest().build();
        }
        PageResult<Film> result = filmService.searchByTitle(keyword, page, size);
        return ResponseEntity.ok(result);
    }

    @GetMapping("/top")
    public ResponseEntity<?> topRented(@RequestParam(defaultValue = "10") int limit) {
        return ResponseEntity.ok(filmService.getTopRented(limit));
    }

    @GetMapping("/overdue")
    public ResponseEntity<?> overdue() {
        return ResponseEntity.ok(filmService.getOverdueFilms());
    }

    @PostMapping
    public ResponseEntity<Film> create(@RequestBody Film film) {
        try {
            Film created = filmService.create(film);
            return ResponseEntity.status(HttpStatus.CREATED).body(created);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @PutMapping("/{id}")
    public ResponseEntity<Film> update(@PathVariable("id") Integer id, @RequestBody Film film) {
        Film existing = filmService.getById(id);
        if (existing == null) {
            return ResponseEntity.notFound().build();
        }
        film.setFilmId(id);
        try {
            Film updated = filmService.update(film);
            return ResponseEntity.ok(updated);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable("id") Integer id) {
        Film existing = filmService.getById(id);
        if (existing == null) {
            return ResponseEntity.notFound().build();
        }
        try {
            filmService.delete(id);
            return ResponseEntity.noContent().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
}
