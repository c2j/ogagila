package com.ogagila.service;

import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.entity.Store;
import com.ogagila.mapper.StoreMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

@Service
@Transactional
public class StoreService {

    private final StoreMapper storeMapper;

    public StoreService(StoreMapper storeMapper) {
        this.storeMapper = storeMapper;
    }

    @Transactional(readOnly = true)
    public PageResult<Store> getAll(int page, int size) {
        int offset = (page - 1) * size;
        List<Store> stores = storeMapper.selectAll(offset, size);
        long total = storeMapper.countAll();
        return new PageResult<>(stores, total, page, size);
    }

    @Transactional(readOnly = true)
    public Store getById(Integer storeId) {
        return storeMapper.selectById(storeId);
    }

    @Transactional(readOnly = true)
    public Store getWithManager(Integer storeId) {
        return storeMapper.selectWithManager(storeId);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> getSalesReport(Integer storeId) {
        return storeMapper.selectSalesReport(storeId);
    }
}
