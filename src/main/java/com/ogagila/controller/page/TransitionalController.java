package com.ogagila.controller.page;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.ogagila.service.CustomerService;
import com.ogagila.service.FilmService;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.servlet.ModelAndView;

/**
 * TRANSITIONAL controller - JSP pages that embed Vue 3 components via CDN
 * for progressive modernization. The JSP provides a shell with initial data
 * as JSON, and Vue handles interactivity on the client side.
 */
@Controller
@RequestMapping("/modern")
public class TransitionalController {

    private final FilmService filmService;
    private final CustomerService customerService;
    private final ObjectMapper objectMapper;

    public TransitionalController(FilmService filmService,
                                  CustomerService customerService,
                                  ObjectMapper objectMapper) {
        this.filmService = filmService;
        this.customerService = customerService;
        this.objectMapper = objectMapper;
    }

    @GetMapping("/film-catalog")
    public ModelAndView filmCatalog() {
        ModelAndView mav = new ModelAndView("modern/film-catalog-vue");
        try {
            String filmListJson = objectMapper.writeValueAsString(
                    filmService.getAll(1, 100).getList());
            mav.addObject("filmListJson", filmListJson);
        } catch (JsonProcessingException e) {
            mav.addObject("filmListJson", "[]");
        }
        return mav;
    }

    @GetMapping("/customer-search")
    public ModelAndView customerSearch() {
        ModelAndView mav = new ModelAndView("modern/customer-search-vue");
        try {
            String customerListJson = objectMapper.writeValueAsString(
                    customerService.getAll(1, 100).getList());
            mav.addObject("customerListJson", customerListJson);
        } catch (JsonProcessingException e) {
            mav.addObject("customerListJson", "[]");
        }
        return mav;
    }
}
