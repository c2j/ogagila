package com.ogagila.mapper;

import com.ogagila.entity.Inventory;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface InventoryMapper {

    List<Inventory> selectAll();

    List<Inventory> selectByStore(@Param("storeId") Integer storeId);

    List<Inventory> selectByFilm(@Param("filmId") Integer filmId);

    Boolean checkInStock(@Param("filmId") Integer filmId, @Param("storeId") Integer storeId);

    int insert(Inventory inventory);

    int update(Inventory inventory);
}
