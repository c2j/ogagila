package com.ogagila.controller.page;

import com.ogagila.mapper.RentalMapper;
import com.ogagila.service.RentalService;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.ModelAndView;

/**
 * GEN2 (Semi-Modernized) controller for legacy rental management pages.
 * Uses MyBatis mappers via service layer with GaussDB-specific queries.
 */
@Controller
@RequestMapping("/legacy/rentals")
public class LegacyRentalController {

    private final RentalService rentalService;
    private final RentalMapper rentalMapper;

    public LegacyRentalController(RentalService rentalService, RentalMapper rentalMapper) {
        this.rentalService = rentalService;
        this.rentalMapper = rentalMapper;
    }

    @GetMapping
    public ModelAndView list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "50") int size) {
        ModelAndView mav = new ModelAndView("legacy/rental-list");
        mav.addObject("rentals", rentalService.getAll(page, size));
        mav.addObject("page", page);
        mav.addObject("size", size);
        return mav;
    }

    @GetMapping("/overdue")
    public ModelAndView overdue() {
        ModelAndView mav = new ModelAndView("legacy/overdue");
        mav.addObject("overdueRentals", rentalMapper.selectOverdue());
        return mav;
    }
}
