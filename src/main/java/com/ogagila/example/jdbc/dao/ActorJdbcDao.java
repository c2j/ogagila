package com.ogagila.example.jdbc.dao;

import java.sql.*;
import java.util.ArrayList;
import java.util.List;
import javax.sql.DataSource;

/**
 * Actor JDBC DAO — 纯 JDBC 数据访问对象。
 * <p>
 * 演示 JSP 在同一个页面中调用多个 DAO 的经典模式。
 */
public class ActorJdbcDao {

    private final DataSource dataSource;

    public ActorJdbcDao(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    /**
     * 查询所有演员（带分页）。
     */
    public List<ActorRow> findAll(int page, int pageSize) throws SQLException {
        String sql = "SELECT actor_id, first_name, last_name, last_update FROM actor ORDER BY actor_id LIMIT ? OFFSET ?";
        List<ActorRow> actors = new ArrayList<>();
        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, pageSize);
            ps.setInt(2, (page - 1) * pageSize);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    ActorRow a = new ActorRow();
                    a.actorId = rs.getInt("actor_id");
                    a.firstName = rs.getString("first_name");
                    a.lastName = rs.getString("last_name");
                    a.lastUpdate = rs.getTimestamp("last_update");
                    actors.add(a);
                }
            }
        }
        return actors;
    }

    /**
     * 查询演员总数。
     */
    public long count() throws SQLException {
        String sql = "SELECT COUNT(*) FROM actor";
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
     * 查询某部电影的所有演员。
     */
    public List<ActorRow> findByFilmId(int filmId) throws SQLException {
        String sql = "SELECT a.actor_id, a.first_name, a.last_name, a.last_update FROM actor a JOIN film_actor fa ON a.actor_id = fa.actor_id WHERE fa.film_id = ? ORDER BY a.actor_id";
        List<ActorRow> actors = new ArrayList<>();
        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, filmId);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) {
                    ActorRow a = new ActorRow();
                    a.actorId = rs.getInt("actor_id");
                    a.firstName = rs.getString("first_name");
                    a.lastName = rs.getString("last_name");
                    a.lastUpdate = rs.getTimestamp("last_update");
                    actors.add(a);
                }
            }
        }
        return actors;
    }

    /** 演员行数据传输对象 */
    public static class ActorRow {
        public int actorId;
        public String firstName;
        public String lastName;
        public Timestamp lastUpdate;
    }
}
