package com.ogagila.service;

import com.ogagila.controller.api.dto.PageResult;
import com.ogagila.controller.api.dto.PaymentDetailDTO;
import com.ogagila.entity.Customer;
import com.ogagila.entity.Payment;
import com.ogagila.mapper.CustomerMapper;
import com.ogagila.mapper.PaymentMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@Transactional
public class PaymentService {

    private final PaymentMapper paymentMapper;
    private final CustomerMapper customerMapper;

    public PaymentService(PaymentMapper paymentMapper, CustomerMapper customerMapper) {
        this.paymentMapper = paymentMapper;
        this.customerMapper = customerMapper;
    }

    @Transactional(readOnly = true)
    public PageResult<Payment> getAll(int page, int size) {
        int offset = (page - 1) * size;
        List<Payment> payments = paymentMapper.selectAll(offset, size);
        long total = paymentMapper.countAll();
        return new PageResult<>(payments, total, page, size);
    }

    @Transactional(readOnly = true)
    public Payment getById(Integer paymentId) {
        return paymentMapper.selectById(paymentId);
    }

    @Transactional(readOnly = true)
    public List<Payment> getByCustomer(Integer customerId) {
        return paymentMapper.selectByCustomer(customerId);
    }

    @Transactional(readOnly = true)
    public List<PaymentDetailDTO> getByCustomerWithDetails(Integer customerId) {
        List<Payment> payments = paymentMapper.selectByCustomer(customerId);
        return payments.stream().map(p -> {
            Customer c = customerMapper.selectById(p.getCustomerId());
            String name = (c != null) ? c.getFirstName() + " " + c.getLastName() : null;
            return new PaymentDetailDTO(p, name);
        }).collect(Collectors.toList());
    }

    public Payment create(Payment payment) {
        if (payment.getPaymentDate() == null) {
            payment.setPaymentDate(OffsetDateTime.now());
        }
        paymentMapper.insert(payment);
        return payment;
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> getMonthlyTotal(Integer year, Integer month) {
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
        return paymentMapper.selectMonthlyTotal(startDate, endDate);
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> getPartitionInfo() {
        return paymentMapper.selectPartitionInfo();
    }

    @Transactional(readOnly = true)
    public List<Map<String, Object>> getDailyRevenue(Integer year, Integer month) {
        int y = (year != null) ? year : LocalDate.now().getYear();
        int m = (month != null) ? month : LocalDate.now().getMonthValue();
        OffsetDateTime startDate = OffsetDateTime.of(y, m, 1, 0, 0, 0, 0, ZoneOffset.UTC);
        OffsetDateTime endDate = startDate.plusMonths(1);
        return paymentMapper.selectDailyRevenue(startDate, endDate);
    }
}
