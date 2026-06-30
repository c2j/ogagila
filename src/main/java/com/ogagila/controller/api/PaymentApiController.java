package com.ogagila.controller.api;

import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.controller.api.dto.PaymentDetailDTO;
import com.ogagila.entity.Payment;
import com.ogagila.service.PaymentService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/payments")
@CrossOrigin(origins = {"http://localhost:5173", "http://localhost:8080"})
public class PaymentApiController {

    private final PaymentService paymentService;

    public PaymentApiController(PaymentService paymentService) {
        this.paymentService = paymentService;
    }

    @GetMapping
    public ResponseEntity<PageResult<Payment>> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int size) {
        PageResult<Payment> result = paymentService.getAll(page, size);
        return ResponseEntity.ok(result);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Payment> getById(@PathVariable("id") Integer id) {
        Payment payment = paymentService.getById(id);
        if (payment == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(payment);
    }

    @GetMapping("/by-customer/{customerId}")
    public ResponseEntity<List<PaymentDetailDTO>> byCustomer(
            @PathVariable("customerId") Integer customerId) {
        List<PaymentDetailDTO> payments = paymentService.getByCustomerWithDetails(customerId);
        return ResponseEntity.ok(payments);
    }

    @GetMapping("/monthly-revenue")
    public ResponseEntity<List<Map<String, Object>>> monthlyRevenue(
            @RequestParam(required = false) Integer year,
            @RequestParam(required = false) Integer month) {
        List<Map<String, Object>> result = paymentService.getMonthlyTotal(year, month);
        return ResponseEntity.ok(result);
    }

    @GetMapping("/daily-revenue")
    public ResponseEntity<List<Map<String, Object>>> dailyRevenue(
            @RequestParam(required = false) Integer year,
            @RequestParam(required = false) Integer month) {
        List<Map<String, Object>> result = paymentService.getDailyRevenue(year, month);
        return ResponseEntity.ok(result);
    }

    @GetMapping("/partition-info")
    public ResponseEntity<List<Map<String, Object>>> partitionInfo() {
        List<Map<String, Object>> info = paymentService.getPartitionInfo();
        return ResponseEntity.ok(info);
    }

    @PostMapping
    public ResponseEntity<Payment> create(@RequestBody Payment payment) {
        try {
            Payment created = paymentService.create(payment);
            return ResponseEntity.status(HttpStatus.CREATED).body(created);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }
}
