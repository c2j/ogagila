package com.ogagila.controller.page;

import javax.sql.DataSource;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.servlet.ModelAndView;

/**
 * GEN1 (Extreme Legacy) controller.
 * This controller ONLY passes the DataSource to the JSP.
 * ALL SQL execution happens directly in the JSP using raw JDBC.
 * This simulates a production system from 2008 where developers wrote
 * JDBC code directly in presentation layer.
 *
 * WARNING: This pattern is for demonstration purposes only.
 * DO NOT replicate this pattern in modern development.
 */
@Controller
@RequestMapping("/legacy/raw-sql")
public class LegacyRawSqlController {

    private final DataSource dataSource;

    public LegacyRawSqlController(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @GetMapping("/rental-stats")
    public ModelAndView rentalStats() {
        ModelAndView mav = new ModelAndView("legacy/rental-stats-raw");
        mav.addObject("datasource", dataSource);
        return mav;
    }

    @GetMapping("/film-count")
    public ModelAndView filmCount() {
        ModelAndView mav = new ModelAndView("legacy/film-count-raw");
        mav.addObject("datasource", dataSource);
        return mav;
    }
}
