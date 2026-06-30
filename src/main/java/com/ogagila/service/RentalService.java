package com.ogagila.service;

import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.entity.Rental;
import com.ogagila.mapper.RentalMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

@Service
@Transactional
public class RentalService {

    private final RentalMapper rentalMapper;

    public RentalService(RentalMapper rentalMapper) {
        this.rentalMapper = rentalMapper;
    }

    @Transactional(readOnly = true)
    public PageResult<Rental> getAll(int page, int size) {
        int offset = (page - 1) * size;
        List<Rental> rentals = rentalMapper.selectAll(offset, size);
        long total = rentalMapper.countAll();
        return new PageResult<>(rentals, total, page, size);
    }

    @Transactional(readOnly = true)
    public Rental getById(Integer rentalId) {
        return rentalMapper.selectById(rentalId);
    }

    @Transactional(readOnly = true)
    public List<Rental> getOverdue() {
        return rentalMapper.selectOverdue();
    }

    @Transactional(readOnly = true)
    public List<Rental> getByCustomer(Integer customerId) {
        return rentalMapper.selectByCustomer(customerId);
    }

    public Rental create(Rental rental) {
        if (rental.getRentalDate() == null) {
            rental.setRentalDate(OffsetDateTime.now());
        }
        rentalMapper.insert(rental);
        return rental;
    }

    public void updateReturn(Integer rentalId) {
        rentalMapper.updateReturn(rentalId, OffsetDateTime.now());
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> getMonthlyStats(Integer year, Integer month) {
        int y = (year != null) ? year : LocalDate.now().getYear();
        OffsetDateTime startDate;
        OffsetDateTime endDate;
        if (month != null) {
            startDate = OffsetDateTime.of(y, month, 1, 0, 0, 0, 0, ZoneOffset.UTC);
            endDate = startDate.plusMonths(1);
        } else {
            startDate = OffsetDateTime.of(y, 1, 1, 0, 0, 0, 0, ZoneOffset.UTC);
            endDate = OffsetDateTime.of(y + 1, 1, 1, 0, 0, 0, 0, ZoneOffset.UTC);
        }
        return rentalMapper.selectMonthlyStats(startDate, endDate);
    }
}
