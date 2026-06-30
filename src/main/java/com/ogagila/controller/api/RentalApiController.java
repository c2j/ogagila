package com.ogagila.controller.api;

import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.entity.Rental;
import com.ogagila.service.RentalService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/rentals")
@CrossOrigin(origins = {"http://localhost:5173", "http://localhost:8080"})
public class RentalApiController {

    private final RentalService rentalService;

    public RentalApiController(RentalService rentalService) {
        this.rentalService = rentalService;
    }

    @GetMapping
    public ResponseEntity<PageResult<Rental>> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int size) {
        PageResult<Rental> result = rentalService.getAll(page, size);
        return ResponseEntity.ok(result);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Rental> getById(@PathVariable("id") Integer id) {
        Rental rental = rentalService.getById(id);
        if (rental == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(rental);
    }

    @GetMapping("/overdue")
    public ResponseEntity<List<Rental>> overdue() {
        List<Rental> rentals = rentalService.getOverdue();
        return ResponseEntity.ok(rentals);
    }

    @GetMapping("/by-customer/{customerId}")
    public ResponseEntity<List<Rental>> byCustomer(@PathVariable("customerId") Integer customerId) {
        List<Rental> rentals = rentalService.getByCustomer(customerId);
        return ResponseEntity.ok(rentals);
    }

    @GetMapping("/monthly-stats")
    public ResponseEntity<List<Map<String, Object>>> monthlyStats(
            @RequestParam(required = false) Integer year,
            @RequestParam(required = false) Integer month) {
        List<Map<String, Object>> stats = rentalService.getMonthlyStats(year, month);
        return ResponseEntity.ok(stats);
    }

    @PostMapping
    public ResponseEntity<Rental> create(@RequestBody Rental rental) {
        try {
            Rental created = rentalService.create(rental);
            return ResponseEntity.status(HttpStatus.CREATED).body(created);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @PutMapping("/{id}/return")
    public ResponseEntity<Void> updateReturn(@PathVariable("id") Integer id) {
        Rental existing = rentalService.getById(id);
        if (existing == null) {
            return ResponseEntity.notFound().build();
        }
        if (existing.getReturnDate() != null) {
            return ResponseEntity.badRequest().build();
        }
        try {
            rentalService.updateReturn(id);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
}
