package com.ogagila.mapper;

import com.ogagila.entity.Staff;
import org.apache.ibatis.annotations.Param;

import java.util.List;

public interface StaffMapper {

    List<Staff> selectAll();

    Staff selectById(@Param("staffId") Integer staffId);

    int insert(Staff staff);

    int update(Staff staff);
}
