package com.ogagila.controller.api;

import com.ogagila.controller.api.dto.DashboardDTO;
import com.ogagila.service.ReportService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/reports")
@CrossOrigin(origins = {"http://localhost:5173", "http://localhost:8080"})
public class ReportApiController {

    private final ReportService reportService;

    public ReportApiController(ReportService reportService) {
        this.reportService = reportService;
    }

    @GetMapping("/dashboard")
    public ResponseEntity<DashboardDTO> dashboard() {
        DashboardDTO dashboard = reportService.getDashboard();
        return ResponseEntity.ok(dashboard);
    }

    @GetMapping("/sales-by-category")
    public ResponseEntity<List<Map<String, Object>>> salesByCategory() {
        return ResponseEntity.ok(reportService.getSalesByCategory());
    }

    @GetMapping("/sales-by-store")
    public ResponseEntity<List<Map<String, Object>>> salesByStore() {
        return ResponseEntity.ok(reportService.getSalesByStore());
    }

    @GetMapping("/top-films")
    public ResponseEntity<List<Map<String, Object>>> topFilms(
            @RequestParam(defaultValue = "10") int limit) {
        return ResponseEntity.ok(reportService.getTopFilms(limit));
    }

    @GetMapping("/top-actors")
    public ResponseEntity<List<Map<String, Object>>> topActors(
            @RequestParam(defaultValue = "10") int limit) {
        return ResponseEntity.ok(reportService.getTopActors(limit));
    }

    @GetMapping("/monthly-revenue")
    public ResponseEntity<List<Map<String, Object>>> monthlyRevenue(
            @RequestParam(required = false) Integer year) {
        return ResponseEntity.ok(reportService.getMonthlyRevenue(year));
    }

    @GetMapping("/customer-activity")
    public ResponseEntity<List<Map<String, Object>>> customerActivity(
            @RequestParam(defaultValue = "20") int limit) {
        return ResponseEntity.ok(reportService.getCustomerActivity(limit));
    }
}
