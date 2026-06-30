package com.ogagila.service;

import com.ogagila.entity.Category;
import com.ogagila.mapper.CategoryMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class CategoryService {

    private final CategoryMapper categoryMapper;

    public CategoryService(CategoryMapper categoryMapper) {
        this.categoryMapper = categoryMapper;
    }

    @Transactional(readOnly = true)
    public List<Category> getAll() {
        return categoryMapper.selectAll();
    }

    @Transactional(readOnly = true)
    public Category getById(Integer categoryId) {
        return categoryMapper.selectById(categoryId);
    }

    public Category create(Category category) {
        categoryMapper.insert(category);
        return category;
    }

    public Category update(Category category) {
        categoryMapper.update(category);
        return category;
    }
}
