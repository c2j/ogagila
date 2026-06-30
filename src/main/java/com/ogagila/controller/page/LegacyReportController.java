package com.ogagila.controller.page;

import com.ogagila.service.ReportService;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.ModelAndView;

/**
 * GEN2 (Semi-Modernized) controller for legacy report pages.
 * Uses MyBatis mappers via ReportService.
 */
@Controller
@RequestMapping("/legacy/reports")
public class LegacyReportController {

    private final ReportService reportService;

    public LegacyReportController(ReportService reportService) {
        this.reportService = reportService;
    }

    @GetMapping("/sales")
    public ModelAndView sales() {
        ModelAndView mav = new ModelAndView("legacy/sales-report");
        mav.addObject("salesByCategory", reportService.getSalesByCategory());
        mav.addObject("salesByStore", reportService.getSalesByStore());
        return mav;
    }

    @GetMapping("/top-films")
    public ModelAndView topFilms(@RequestParam(defaultValue = "50") int limit) {
        ModelAndView mav = new ModelAndView("legacy/top-films");
        mav.addObject("topFilms", reportService.getTopFilms(limit));
        return mav;
    }
}
