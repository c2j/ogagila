package com.ogagila;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.support.SpringBootServletInitializer;

/**
 * ogagila-web - openGauss Pagila DVD Rental Management System
 *
 * Multi-generation tech stack:
 *   Gen1: Pure JSP + raw SQL in JSP (extreme legacy)
 *   Gen2: JSP + MyBatis mapper (semi-modernized)
 *   Gen3: Vue 3 SPA + REST API + MyBatis (modern)
 *
 * GaussDB features demonstrated:
 *   - Partitioned tables (payment with pruning)
 *   - Full-text search (tsvector/GIN index)
 *   - Stored procedures via MyBatis
 *   - JSONB operations
 *   - Oracle-compatible syntax (CONNECT BY, etc.)
 *   - Window functions (RANK, ROW_NUMBER, etc.)
 *   - Custom aggregates (group_concat)
 *   - Materialized views
 */
@SpringBootApplication
@MapperScan("com.ogagila.mapper")
public class OgagilaApplication extends SpringBootServletInitializer {

    public static void main(String[] args) {
        SpringApplication.run(OgagilaApplication.class, args);
        System.out.println("===============================================");
        System.out.println("  ogagila-web started successfully!");
        System.out.println("  Legacy JSP:  http://localhost:8080/ogagila/");
        System.out.println("  Modern Vue:  http://localhost:8080/ogagila/static/vue/");
        System.out.println("  REST API:    http://localhost:8080/ogagila/api/");
        System.out.println("===============================================");
    }
}
