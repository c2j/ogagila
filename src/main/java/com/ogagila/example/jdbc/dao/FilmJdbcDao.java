package com.ogagila.example.jdbc.dao;

import java.math.BigDecimal;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;
import javax.sql.DataSource;

/**
 * Film JDBC DAO — 纯 JDBC 实现的数据访问对象。
 * <p>
 * 这是 GEN1.5 模式：DAO 封装所有 SQL/JDBC，JSP 只负责调用 DAO 方法并渲染结果。
 * JSP 不再直接写 SQL，而是通过 DAO 获取数据。
 * <p>
 * 构造函数接收 DataSource（从 JSP request 属性获取或 Controller 注入），
 * 每个方法独立获取和释放连接。
 */
public class FilmJdbcDao {

    private final DataSource dataSource;

    public FilmJdbcDao(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    /**
     * 查询所有电影（带分页）。
     */
    public List<FilmRow> findAll(int page, int pageSize) throws SQLException {
        String sql = "SELECT film_id, title, release_year, rating, length, rental_rate, rental_duration FROM film ORDER BY film_id LIMIT ? OFFSET ?";
        List<FilmRow> films = new ArrayList<>();
        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, pageSize);
            ps.setInt(2, (page - 1) * pageSize);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    films.add(mapRow(rs));
                }
            }
        }
        return films;
    }

    /**
     * 按 ID 查询单部电影详情。
     */
    public FilmRow findById(int filmId) throws SQLException {
        String sql = "SELECT film_id, title, description, release_year, rating, length, rental_rate, rental_duration, replacement_cost FROM film WHERE film_id = ?";
        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, filmId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    FilmRow f = mapRow(rs);
                    f.description = rs.getString("description");
                    f.replacementCost = rs.getBigDecimal("replacement_cost");
                    return f;
                }
            }
        }
        return null;
    }

    /**
     * 按片名模糊搜索。
     */
    public List<FilmRow> searchByTitle(String keyword, int page, int pageSize) throws SQLException {
        String sql = "SELECT film_id, title, release_year, rating, length, rental_rate, rental_duration FROM film WHERE title ILIKE ? ORDER BY film_id LIMIT ? OFFSET ?";
        List<FilmRow> films = new ArrayList<>();
        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, "%" + keyword + "%");
            ps.setInt(2, pageSize);
            ps.setInt(3, (page - 1) * pageSize);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    films.add(mapRow(rs));
                }
            }
        }
        return films;
    }

    /**
     * 查询电影总数。
     */
    public long count() throws SQLException {
        String sql = "SELECT COUNT(*) FROM film";
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            if (rs.next()) {
                return rs.getLong(1);
            }
        }
        return 0;
    }

    /**
     * 按分级统计电影数量。
     */
    public List<RatingCount> countByRating() throws SQLException {
        String sql = "SELECT rating::text AS rating_name, COUNT(*) AS cnt FROM film GROUP BY rating ORDER BY cnt DESC";
        List<RatingCount> result = new ArrayList<>();
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                RatingCount rc = new RatingCount();
                rc.rating = rs.getString("rating_name");
                rc.count = rs.getLong("cnt");
                result.add(rc);
            }
        }
        return result;
    }

    private FilmRow mapRow(ResultSet rs) throws SQLException {
        FilmRow f = new FilmRow();
        f.filmId = rs.getInt("film_id");
        f.title = rs.getString("title");
        f.releaseYear = rs.getObject("release_year", Integer.class);
        f.rating = rs.getString("rating");
        f.length = rs.getObject("length", Integer.class);
        f.rentalRate = rs.getBigDecimal("rental_rate");
        f.rentalDuration = rs.getObject("rental_duration", Integer.class);
        return f;
    }

    /** 电影行数据传输对象 */
    public static class FilmRow {
        public int filmId;
        public String title;
        public String description;
        public Integer releaseYear;
        public String rating;
        public Integer length;
        public BigDecimal rentalRate;
        public Integer rentalDuration;
        public BigDecimal replacementCost;
    }

    /** 分级统计 DTO */
    public static class RatingCount {
        public String rating;
        public long count;
    }
}
