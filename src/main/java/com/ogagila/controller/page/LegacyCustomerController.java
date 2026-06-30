package com.ogagila.controller.page;

import com.ogagila.mapper.CustomerMapper;
import com.ogagila.mapper.ProcedureMapper;
import com.ogagila.mapper.RentalMapper;
import com.ogagila.service.CustomerService;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.ModelAndView;

/**
 * GEN2 (Semi-Modernized) controller for legacy customer management pages.
 * Uses MyBatis mappers via service layer.
 */
@Controller
@RequestMapping("/legacy/customers")
public class LegacyCustomerController {

    private final CustomerService customerService;
    private final CustomerMapper customerMapper;
    private final RentalMapper rentalMapper;
    private final ProcedureMapper procedureMapper;

    public LegacyCustomerController(CustomerService customerService,
                                    CustomerMapper customerMapper,
                                    RentalMapper rentalMapper,
                                    ProcedureMapper procedureMapper) {
        this.customerService = customerService;
        this.customerMapper = customerMapper;
        this.rentalMapper = rentalMapper;
        this.procedureMapper = procedureMapper;
    }

    @GetMapping
    public ModelAndView list(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "50") int size) {
        ModelAndView mav = new ModelAndView("legacy/customer-list");
        mav.addObject("customers", customerService.getAll(page, size));
        mav.addObject("page", page);
        mav.addObject("size", size);
        return mav;
    }

    @GetMapping("/{id}")
    public ModelAndView detail(@PathVariable("id") Integer id) {
        ModelAndView mav = new ModelAndView("legacy/customer-detail");
        mav.addObject("detail", customerService.getDetail(id));
        mav.addObject("rentals", rentalMapper.selectByCustomer(id));
        mav.addObject("balance", procedureMapper.getCustomerBalance(id));
        return mav;
    }
}
