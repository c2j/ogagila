package com.ogagila.controller.page;

import com.ogagila.entity.Film;
import com.ogagila.mapper.FilmMapper;
import com.ogagila.service.FilmService;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.ModelAndView;

/**
 * GEN2 (Semi-Modernized) controller for legacy film management pages.
 * Uses MyBatis mappers via service layer - proper separation but JSP rendering.
 */
@Controller
@RequestMapping("/legacy/films")
public class LegacyFilmController {

    private final FilmService filmService;
    private final FilmMapper filmMapper;

    public LegacyFilmController(FilmService filmService, FilmMapper filmMapper) {
        this.filmService = filmService;
        this.filmMapper = filmMapper;
    }

    @GetMapping
    public ModelAndView list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "50") int size) {
        ModelAndView mav = new ModelAndView("legacy/film-list");
        mav.addObject("films", filmService.getAll(page, size));
        mav.addObject("page", page);
        mav.addObject("size", size);
        return mav;
    }

    @GetMapping("/{id}")
    public ModelAndView detail(@PathVariable("id") Integer id) {
        ModelAndView mav = new ModelAndView("legacy/film-detail");
        mav.addObject("detail", filmService.getDetail(id));
        mav.addObject("overdue", filmMapper.selectOverdueFilms());
        return mav;
    }

    @GetMapping("/search")
    public ModelAndView search(
            @RequestParam String keyword,
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "50") int size) {
        ModelAndView mav = new ModelAndView("legacy/film-list");
        mav.addObject("films", filmService.searchByTitle(keyword, page, size));
        mav.addObject("keyword", keyword);
        mav.addObject("page", page);
        mav.addObject("size", size);
        return mav;
    }
}
