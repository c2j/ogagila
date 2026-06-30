package com.ogagila.service;

import com.ogagila.entity.Inventory;
import com.ogagila.mapper.InventoryMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class InventoryService {

    private final InventoryMapper inventoryMapper;

    public InventoryService(InventoryMapper inventoryMapper) {
        this.inventoryMapper = inventoryMapper;
    }

    @Transactional(readOnly = true)
    public List<Inventory> getAll() {
        return inventoryMapper.selectAll();
    }

    @Transactional(readOnly = true)
    public List<Inventory> getByStore(Integer storeId) {
        return inventoryMapper.selectByStore(storeId);
    }

    @Transactional(readOnly = true)
    public List<Inventory> getByFilm(Integer filmId) {
        return inventoryMapper.selectByFilm(filmId);
    }

    @Transactional(readOnly = true)
    public Boolean checkInStock(Integer filmId, Integer storeId) {
        return inventoryMapper.checkInStock(filmId, storeId);
    }

    public Inventory create(Inventory inventory) {
        inventoryMapper.insert(inventory);
        return inventory;
    }

    public Inventory update(Inventory inventory) {
        inventoryMapper.update(inventory);
        return inventory;
    }
}
