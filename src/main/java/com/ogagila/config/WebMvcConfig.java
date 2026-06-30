package com.ogagila.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.ViewControllerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/**
 * Web MVC configuration
 *
 * Handles:
 * - Static resource mapping for Vue SPA
 * - Simple view controller shortcuts
 * - JSP view resolution (Spring Boot auto-config handles prefix/suffix)
 */
@Configuration
public class WebMvcConfig implements WebMvcConfigurer {

    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        // Vue SPA static resources
        registry.addResourceHandler("/vue/**")
                .addResourceLocations("classpath:/static/vue/");

        // General static resources
        registry.addResourceHandler("/css/**", "/js/**", "/img/**")
                .addResourceLocations("classpath:/static/css/",
                                     "classpath:/static/js/");
    }

    @Override
    public void addViewControllers(ViewControllerRegistry registry) {
        // Root redirect to legacy dashboard
        registry.addRedirectViewController("/", "/legacy/dashboard");

        // Vue SPA entry point
        registry.addViewController("/vue").setViewName("forward:/vue/index.html");
        registry.addViewController("/vue/").setViewName("forward:/vue/index.html");
    }
}
