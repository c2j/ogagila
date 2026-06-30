package com.ogagila.controller.api;

import com.ogagila.mapper.ProcedureMapper;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/procedures")
@CrossOrigin(origins = {"http://localhost:5173", "http://localhost:8080"})
public class ProcedureApiController {

    private final ProcedureMapper procedureMapper;

    public ProcedureApiController(ProcedureMapper procedureMapper) {
        this.procedureMapper = procedureMapper;
    }

    @GetMapping("/film-in-stock/{filmId}/{storeId}")
    public ResponseEntity<Map<String, Object>> filmInStock(
            @PathVariable("filmId") Integer filmId,
            @PathVariable("storeId") Integer storeId) {
        try {
            Map<String, Object> result = procedureMapper.filmInStock(filmId, storeId);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping("/customer-balance/{customerId}")
    public ResponseEntity<Map<String, Object>> customerBalance(
            @PathVariable("customerId") Integer customerId) {
        try {
            Map<String, Object> result = procedureMapper.getCustomerBalance(customerId);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping("/rewards-report")
    public ResponseEntity<Map<String, Object>> rewardsReport(
            @RequestParam(defaultValue = "10") int minPurchases,
            @RequestParam(defaultValue = "50") double minAmount) {
        try {
            Map<String, Object> result = procedureMapper.rewardsReport(minPurchases, minAmount);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().build();
        }
    }

    @GetMapping("/inventory-in-stock/{inventoryId}")
    public ResponseEntity<Map<String, Object>> inventoryInStock(
            @PathVariable("inventoryId") Integer inventoryId) {
        try {
            Map<String, Object> result = procedureMapper.inventoryInStock(inventoryId);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.internalServerError().build();
        }
    }
}
