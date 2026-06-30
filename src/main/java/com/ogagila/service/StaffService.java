package com.ogagila.service;

import com.ogagila.entity.Staff;
import com.ogagila.mapper.StaffMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class StaffService {

    private final StaffMapper staffMapper;

    public StaffService(StaffMapper staffMapper) {
        this.staffMapper = staffMapper;
    }

    @Transactional(readOnly = true)
    public List<Staff> getAll() {
        return staffMapper.selectAll();
    }

    @Transactional(readOnly = true)
    public Staff getById(Integer staffId) {
        return staffMapper.selectById(staffId);
    }

    public Staff create(Staff staff) {
        staffMapper.insert(staff);
        return staff;
    }

    public Staff update(Staff staff) {
        staffMapper.update(staff);
        return staff;
    }
}
