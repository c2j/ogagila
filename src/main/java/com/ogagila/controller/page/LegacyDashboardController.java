package com.ogagila.controller.page;

import com.ogagila.service.ReportService;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.servlet.ModelAndView;

/**
 * GEN2 (Semi-Modernized) controller for the legacy system dashboard.
 * Uses MyBatis-backed ReportService but renders via JSP.
 */
@Controller
@RequestMapping("/legacy/dashboard")
public class LegacyDashboardController {

    private final ReportService reportService;

    public LegacyDashboardController(ReportService reportService) {
        this.reportService = reportService;
    }

    @GetMapping
    public ModelAndView dashboard() {
        ModelAndView mav = new ModelAndView("legacy/dashboard");
        mav.addObject("dashboard", reportService.getDashboard());
        mav.addObject("salesByCategory", reportService.getSalesByCategory());
        return mav;
    }
}
