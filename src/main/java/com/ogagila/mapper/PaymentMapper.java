package com.ogagila.mapper;

import com.ogagila.entity.Payment;
import org.apache.ibatis.annotations.Param;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

public interface PaymentMapper {

    List<Payment> selectAll(@Param("offset") Integer offset, @Param("limit") Integer limit);

    int countAll();

    Payment selectById(@Param("paymentId") Integer paymentId);

    List<Payment> selectByCustomer(@Param("customerId") Integer customerId);

    int insert(Payment payment);

    List<Map<String, Object>> selectMonthlyTotal(@Param("startDate") OffsetDateTime startDate,
                                                  @Param("endDate") OffsetDateTime endDate);

    List<Map<String, Object>> selectPartitionInfo();

    List<Map<String, Object>> selectDailyRevenue(@Param("startDate") OffsetDateTime startDate,
                                                  @Param("endDate") OffsetDateTime endDate);
}
