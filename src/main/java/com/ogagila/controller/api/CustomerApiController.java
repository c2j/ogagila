package com.ogagila.controller.api;

import com.ogagila.controller.api.dto.CustomerDetailDTO;
import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.entity.Customer;
import com.ogagila.service.CustomerService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/customers")
@CrossOrigin(origins = {"http://localhost:5173", "http://localhost:8080"})
public class CustomerApiController {

    private final CustomerService customerService;

    public CustomerApiController(CustomerService customerService) {
        this.customerService = customerService;
    }

    @GetMapping
    public ResponseEntity<PageResult<Customer>> list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int size) {
        PageResult<Customer> result = customerService.getAll(page, size);
        return ResponseEntity.ok(result);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Customer> getById(@PathVariable("id") Integer id) {
        Customer customer = customerService.getById(id);
        if (customer == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(customer);
    }

    @GetMapping("/detail/{id}")
    public ResponseEntity<CustomerDetailDTO> getDetail(@PathVariable("id") Integer id) {
        CustomerDetailDTO detail = customerService.getDetail(id);
        if (detail == null || detail.getCustomer() == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(detail);
    }

    @GetMapping("/high-value")
    public ResponseEntity<?> highValue(
            @RequestParam(defaultValue = "100") double minAmount) {
        return ResponseEntity.ok(customerService.getHighValueCustomers(minAmount));
    }

    @GetMapping("/hierarchical/{storeId}")
    public ResponseEntity<List<Customer>> hierarchical(@PathVariable("storeId") Integer storeId) {
        List<Customer> customers = customerService.getByStoreHierarchical(storeId);
        return ResponseEntity.ok(customers);
    }

    @PostMapping
    public ResponseEntity<Customer> create(@RequestBody Customer customer) {
        try {
            Customer created = customerService.create(customer);
            return ResponseEntity.status(HttpStatus.CREATED).body(created);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @PutMapping("/{id}")
    public ResponseEntity<Customer> update(@PathVariable("id") Integer id,
                                            @RequestBody Customer customer) {
        Customer existing = customerService.getById(id);
        if (existing == null) {
            return ResponseEntity.notFound().build();
        }
        customer.setCustomerId(id);
        try {
            Customer updated = customerService.update(customer);
            return ResponseEntity.ok(updated);
        } catch (Exception e) {
            return ResponseEntity.badRequest().build();
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable("id") Integer id) {
        Customer existing = customerService.getById(id);
        if (existing == null) {
            return ResponseEntity.notFound().build();
        }
        try {
            customerService.delete(id);
            return ResponseEntity.noContent().build();
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }
}
