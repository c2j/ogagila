package com.ogagila.mapper;

import com.ogagila.entity.Category;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface CategoryMapper {

    List<Category> selectAll();

    Category selectById(@Param("categoryId") Integer categoryId);

    int insert(Category category);

    int update(Category category);
}
