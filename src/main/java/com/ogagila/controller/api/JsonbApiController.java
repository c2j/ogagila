package com.ogagila.controller.api;

import com.ogagila.mapper.JsonbMapper;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/jsonb")
@CrossOrigin(origins = {"http://localhost:5173", "http://localhost:8080"})
public class JsonbApiController {

    private final JsonbMapper jsonbMapper;

    public JsonbApiController(JsonbMapper jsonbMapper) {
        this.jsonbMapper = jsonbMapper;
    }

    @GetMapping("/packages-apt")
    public ResponseEntity<List<Map<String, Object>>> packagesApt() {
        List<Map<String, Object>> packages = jsonbMapper.selectPackagesApt();
        return ResponseEntity.ok(packages);
    }

    @GetMapping("/packages-yum")
    public ResponseEntity<List<Map<String, Object>>> packagesYum() {
        List<Map<String, Object>> packages = jsonbMapper.selectPackagesYum();
        return ResponseEntity.ok(packages);
    }

    @GetMapping("/search")
    public ResponseEntity<List<Map<String, Object>>> search(
            @RequestParam String keyword) {
        if (keyword == null || keyword.trim().isEmpty()) {
            return ResponseEntity.badRequest().build();
        }
        List<Map<String, Object>> results = jsonbMapper.searchPackages(keyword.trim());
        return ResponseEntity.ok(results);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Map<String, Object>> getById(@PathVariable("id") Integer id) {
        Map<String, Object> pkg = jsonbMapper.selectPackageById(id);
        if (pkg == null) {
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(pkg);
    }
}
