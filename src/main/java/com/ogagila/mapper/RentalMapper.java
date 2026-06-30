package com.ogagila.mapper;

import com.ogagila.entity.Rental;
import org.apache.ibatis.annotations.Param;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

public interface RentalMapper {

    List<Rental> selectAll(@Param("offset") Integer offset, @Param("limit") Integer limit);

    int countAll();

    Rental selectById(@Param("rentalId") Integer rentalId);

    List<Rental> selectOverdue();

    List<Rental> selectByCustomer(@Param("customerId") Integer customerId);

    int insert(Rental rental);

    int updateReturn(@Param("rentalId") Integer rentalId,
                     @Param("returnDate") OffsetDateTime returnDate);

    List<Map<String, Object>> selectMonthlyStats(@Param("startDate") OffsetDateTime startDate,
                                                  @Param("endDate") OffsetDateTime endDate);
}
