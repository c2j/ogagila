package com.ogagila.controller.page;

import javax.sql.DataSource;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.ModelAndView;

import com.ogagila.example.jdbc.dao.ActorJdbcDao;
import com.ogagila.example.jdbc.dao.FilmJdbcDao;

/**
 * GEN1.5 (DAO Pattern) — JSP 引用 Java DAO 类的示例。
 * <p>
 * Controller 将 DAO 实例放入 request 属性，JSP 通过 scriptlet 调用 DAO 方法获取数据。
 * 这是 2005 年前后的经典模式：SQL 从 JSP 中抽离到 DAO，但 JSP 仍直接依赖 DAO。
 */
@Controller
@RequestMapping("/legacy/dao-demo")
public class LegacyDaoDemoController {

    private final DataSource dataSource;

    public LegacyDaoDemoController(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    /**
     * 电影列表页 — 通过 FilmJdbcDao + ActorJdbcDao 获取数据。
     * JSP 将:
     *  1. 从 request 获取 DataSource
     *  2. 实例化 FilmJdbcDao 和 ActorJdbcDao
     *  3. 调用 DAO 方法获取数据
     *  4. 用 scriptlet/JSTL 渲染
     */
    @GetMapping("/films")
    public ModelAndView filmList(
            @RequestParam(defaultValue = "1") int page,
            @RequestParam(defaultValue = "20") int pageSize) {

        ModelAndView mav = new ModelAndView("legacy/film-dao-demo");

        // 把 DataSource 传给 JSP，JSP 自己创建 DAO 实例
        // 这是 "JSP 引用 Java 类 DAO" 的核心：JSP 决定何时创建和使用 DAO
        mav.addObject("datasource", dataSource);
        mav.addObject("currentPage", page);
        mav.addObject("pageSize", pageSize);

        return mav;
    }

    /**
     * 电影详情页 — JSP 调用 FilmDao.findById() 和 ActorDao.findByFilmId()。
     */
    @GetMapping("/films/detail")
    public ModelAndView filmDetail(@RequestParam int filmId) {
        ModelAndView mav = new ModelAndView("legacy/film-dao-detail");
        mav.addObject("datasource", dataSource);
        mav.addObject("filmId", filmId);
        return mav;
    }
}
