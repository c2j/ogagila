package com.ogagila.example.jdbc;

import java.math.BigDecimal;
import java.sql.*;
import java.util.ArrayList;
import java.util.List;

import javax.sql.DataSource;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * JDBC 原生 SQL 执行示例合集 - 在 Java 中写 SQL 并调用 JDBC 执行。
 * <p>
 * 覆盖 JDBC 核心操作模式：基本查询、参数化查询、增删改、批量操作、
 * 事务管理、存储函数调用、连接池与 DriverManager 两种连接方式。
 * <p>
 * 所有示例基于 openGauss (PostgreSQL 兼容) + Pagila DVD 租赁数据库。
 *
 * <h3>使用方式</h3>
 * <pre>{@code
 * @Autowired
 * private JdbcExampleService jdbcExampleService;
 *
 * // 在 @PostConstruct 或 CommandLineRunner 中调用示例方法
 * jdbcExampleService.example_basicSelect();
 * }</pre>
 *
 * @author ogagila-examples
 */
@Service
public class JdbcExampleService {

    private static final Logger log = LoggerFactory.getLogger(JdbcExampleService.class);

    // ---------- 连接方式：注入 Spring 管理的 DataSource（连接池） ----------
    private final DataSource dataSource;

    public JdbcExampleService(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    // ========================================================================
    // 示例 1: 基本 SELECT 查询（Statement）
    // ========================================================================

    /**
     * 示例 1: 基本 SELECT 查询 - 使用 Statement 执行最简单的查询。
     * <p>
     * SQL: SELECT film_id, title, release_year FROM film WHERE film_id = 1
     * <p>
     * JDBC 流程: Connection → Statement → executeQuery → ResultSet → close
     */
    public void example1_basicSelect() {
        // language=SQL
        String sql = "SELECT film_id, title, release_year FROM film WHERE film_id = 1";

        /*
         * try-with-resources（Java 7+）自动关闭资源，无需手动 finally 块。
         * 关闭顺序与打开顺序相反：ResultSet → Statement → Connection。
         * Connection 归还给连接池，而非物理关闭。
         */
        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {

            if (rs.next()) {
                int filmId = rs.getInt("film_id");           // 按列名取值
                String title = rs.getString("title");
                Integer releaseYear = rs.getObject("release_year", Integer.class); // JDBC 4.1+ 泛型方法

                log.info("示例1 查询结果: filmId={}, title={}, releaseYear={}", filmId, title, releaseYear);
            }

        } catch (SQLException e) {
            log.error("示例1 查询失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 2: 参数化查询（PreparedStatement）—— 防 SQL 注入
    // ========================================================================

    /**
     * 示例 2: 参数化查询 - 使用 PreparedStatement 防止 SQL 注入。
     * <p>
     * SQL: SELECT film_id, title, rental_rate FROM film
     *      WHERE rating = ?::mpaa_rating AND rental_rate > ?
     *      LIMIT ?
     * <p>
     * 占位符 ? 按位置索引（从 1 开始），JDBC 驱动负责转义参数值。
     */
    public void example2_preparedSelect() {
        // language=SQL
        String sql = """
                SELECT film_id, title, rental_rate
                FROM film
                WHERE rating = ?::mpaa_rating
                  AND rental_rate > ?
                ORDER BY rental_rate DESC
                LIMIT ?
                """;

        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            // 设置参数（索引从 1 开始）
            ps.setString(1, "PG-13");        // 第 1 个 ?
            ps.setBigDecimal(2, new BigDecimal("3.00")); // 第 2 个 ?
            ps.setInt(3, 10);                // 第 3 个 ?

            try (ResultSet rs = ps.executeQuery()) {
                int count = 0;
                while (rs.next()) {
                    count++;
                    log.info("示例2 [{}] filmId={}, title={}, rate={}",
                            count,
                            rs.getInt("film_id"),
                            rs.getString("title"),
                            rs.getBigDecimal("rental_rate"));
                }
                log.info("示例2 共查询到 {} 条记录", count);
            }

        } catch (SQLException e) {
            log.error("示例2 查询失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 3: INSERT 插入数据 + 获取自增主键
    // ========================================================================

    /**
     * 示例 3: INSERT 插入 - 插入新客户并获取数据库生成的 customer_id。
     * <p>
     * SQL: INSERT INTO customer (store_id, first_name, last_name, email,
     *      address_id, activebool, create_date) VALUES (?, ?, ?, ?, ?, ?, ?)
     * <p>
     * Statement.RETURN_GENERATED_KEYS 让数据库返回自增主键值。
     */
    public void example3_insertWithGeneratedKeys() {
        // language=SQL
        String sql = """
                INSERT INTO customer (store_id, first_name, last_name, email, address_id, activebool, create_date)
                VALUES (?, ?, ?, ?, ?, ?, CURRENT_DATE)
                """;

        try (Connection conn = dataSource.getConnection();
             // 第二个参数指定要返回生成的主键
             PreparedStatement ps = conn.prepareStatement(sql, Statement.RETURN_GENERATED_KEYS)) {

            ps.setInt(1, 1);                // store_id
            ps.setString(2, "Zhang");       // first_name
            ps.setString(3, "San");         // last_name
            ps.setString(4, "zhangsan@example.com"); // email
            ps.setInt(5, 1);                // address_id
            ps.setBoolean(6, true);         // activebool

            int affectedRows = ps.executeUpdate();
            log.info("示例3 插入影响行数: {}", affectedRows);

            // 获取生成的主键
            try (ResultSet generatedKeys = ps.getGeneratedKeys()) {
                if (generatedKeys.next()) {
                    int newCustomerId = generatedKeys.getInt(1); // 或 generatedKeys.getInt("customer_id")
                    log.info("示例3 新客户的 customer_id = {}", newCustomerId);
                }
            }

            // 注意: 如果你不想实际修改数据，可以在 conn.setAutoCommit(false) 后 conn.rollback()
            // 或者 DELETE 刚才插入的行

        } catch (SQLException e) {
            log.error("示例3 插入失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 4: UPDATE 更新数据
    // ========================================================================

    /**
     * 示例 4: UPDATE 更新 - 修改客户邮箱。
     * <p>
     * SQL: UPDATE customer SET email = ? WHERE customer_id = ?
     * <p>
     * executeUpdate() 返回受影响的行数（int）。
     */
    public void example4_update() {
        // language=SQL
        String sql = "UPDATE customer SET email = ? WHERE customer_id = ?";

        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            ps.setString(1, "updated@example.com");
            ps.setInt(2, 1);

            int affectedRows = ps.executeUpdate();
            log.info("示例4 更新影响行数: {}", affectedRows);

            if (affectedRows == 0) {
                log.warn("示例4 未找到 customer_id=1 的记录");
            }

        } catch (SQLException e) {
            log.error("示例4 更新失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 5: DELETE 删除数据
    // ========================================================================

    /**
     * 示例 5: DELETE 删除 - 按条件删除。
     * <p>
     * SQL: DELETE FROM actor WHERE first_name = ? AND last_name = ?
     * <p>
     * 注意: 外键约束可能导致删除失败（如 actor 关联了 film_actor）。
     */
    public void example5_delete() {
        // language=SQL
        String sql = "DELETE FROM customer WHERE first_name = ? AND last_name = ? AND email = ?";

        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            ps.setString(1, "Zhang");
            ps.setString(2, "San");
            ps.setString(3, "zhangsan@example.com");

            int affectedRows = ps.executeUpdate();
            log.info("示例5 删除影响行数: {}", affectedRows);

        } catch (SQLException e) {
            log.error("示例5 删除失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 6: 聚合查询 COUNT / SUM / AVG
    // ========================================================================

    /**
     * 示例 6: 聚合查询 - COUNT、SUM、AVG、MIN、MAX。
     * <p>
     * SQL: 统计电影总数、平均租金、最高/最低替换成本。
     */
    public void example6_aggregation() {
        // language=SQL
        String sql = """
                SELECT
                    COUNT(*)                     AS film_count,
                    ROUND(AVG(rental_rate), 2)   AS avg_rental_rate,
                    MIN(replacement_cost)        AS min_replacement,
                    MAX(replacement_cost)        AS max_replacement
                FROM film
                """;

        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {

            if (rs.next()) {
                long filmCount = rs.getLong("film_count");
                BigDecimal avgRate = rs.getBigDecimal("avg_rental_rate");
                BigDecimal minCost = rs.getBigDecimal("min_replacement");
                BigDecimal maxCost = rs.getBigDecimal("max_replacement");

                log.info("示例6 统计: 电影总数={}, 平均租金={}, 替换成本范围=[{}, {}]",
                        filmCount, avgRate, minCost, maxCost);
            }

        } catch (SQLException e) {
            log.error("示例6 聚合查询失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 7: JOIN 多表连接查询 — 将 ResultSet 映射为 Java 对象列表
    // ========================================================================

    /**
     * 示例 7: JOIN 查询 + ResultSet 到 Java 对象的映射。
     * <p>
     * SQL: 查询租金记录，关联客户姓名和电影标题。
     * <p>
     * 这是典型的"手写 JDBC 映射"模式 —— 每拿到一行 rs 数据就 new 一个 DTO。
     */
    public void example7_joinAndMap() {
        // language=SQL
        String sql = """
                SELECT
                    r.rental_id,
                    r.rental_date,
                    r.return_date,
                    c.first_name  AS customer_first_name,
                    c.last_name   AS customer_last_name,
                    f.title       AS film_title
                FROM rental r
                    JOIN customer c ON r.customer_id = c.customer_id
                    JOIN inventory i ON r.inventory_id = i.inventory_id
                    JOIN film f ON i.film_id = f.film_id
                WHERE r.return_date IS NOT NULL
                ORDER BY r.rental_date DESC
                LIMIT 5
                """;

        List<RentalDTO> rentals = new ArrayList<>();

        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql);
             ResultSet rs = ps.executeQuery()) {

            while (rs.next()) {
                RentalDTO dto = new RentalDTO();
                dto.rentalId = rs.getInt("rental_id");
                dto.rentalDate = rs.getTimestamp("rental_date");
                dto.returnDate = rs.getTimestamp("return_date");
                dto.customerName = rs.getString("customer_first_name") + " " + rs.getString("customer_last_name");
                dto.filmTitle = rs.getString("film_title");
                rentals.add(dto);
            }

            log.info("示例7 查询到 {} 条租金记录", rentals.size());
            rentals.forEach(r -> log.info("   {}", r));

        } catch (SQLException e) {
            log.error("示例7 JOIN 查询失败: {}", e.getMessage(), e);
        }
    }

    /** JOIN 查询结果 DTO */
    static class RentalDTO {
        int rentalId;
        Timestamp rentalDate;
        Timestamp returnDate;
        String customerName;
        String filmTitle;

        @Override
        public String toString() {
            return String.format("RentalDTO[id=%d, customer=%s, film=%s, date=%s]",
                    rentalId, customerName, filmTitle, rentalDate);
        }
    }

    // ========================================================================
    // 示例 8: 分页查询 LIMIT / OFFSET
    // ========================================================================

    /**
     * 示例 8: 分页查询 - 使用 LIMIT 和 OFFSET。
     * <p>
     * SQL: SELECT ... FROM film ORDER BY film_id LIMIT ? OFFSET ?
     * <p>
     * 页码 page 从 1 开始，pageSize 为每页条数。
     * OFFSET = (page - 1) * pageSize
     */
    public void example8_pagination(int page, int pageSize) {
        // language=SQL
        String countSql = "SELECT COUNT(*) FROM film";
        // language=SQL
        String dataSql = "SELECT film_id, title, release_year FROM film ORDER BY film_id LIMIT ? OFFSET ?";

        int offset = (page - 1) * pageSize;

        try (Connection conn = dataSource.getConnection()) {

            // 先查总数
            long totalCount;
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery(countSql)) {
                rs.next();
                totalCount = rs.getLong(1);
            }

            // 再查分页数据
            try (PreparedStatement ps = conn.prepareStatement(dataSql)) {
                ps.setInt(1, pageSize);
                ps.setInt(2, offset);
                try (ResultSet rs = ps.executeQuery()) {
                    log.info("示例8 分页查询: page={}, pageSize={}, totalCount={}, offset={}",
                            page, pageSize, totalCount, offset);
                    while (rs.next()) {
                        log.info("   film_id={}, title={}, year={}",
                                rs.getInt("film_id"),
                                rs.getString("title"),
                                rs.getObject("release_year"));
                    }
                }
            }

        } catch (SQLException e) {
            log.error("示例8 分页查询失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 9: 批量操作（Batch）
    // ========================================================================

    /**
     * 示例 9: 批量插入 - 使用 addBatch() / executeBatch() 批量执行。
     * <p>
     * 适用于批量 INSERT、UPDATE、DELETE，减少网络往返次数。
     * <p>
     * openGauss JDBC 配置中 reWriteBatchedInserts=true 会将多条 INSERT
     * 重写为一条多 VALUES 语句，进一步提升性能。
     */
    public void example9_batchInsert() {
        // language=SQL
        String sql = """
                INSERT INTO actor (first_name, last_name)
                VALUES (?, ?)
                """;

        String[][] actors = {
                {"Batch", "Actor1"},
                {"Batch", "Actor2"},
                {"Batch", "Actor3"},
                {"Batch", "Actor4"},
                {"Batch", "Actor5"}
        };

        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            // 关闭自动提交，以便批量失败时回滚
            conn.setAutoCommit(false);

            for (String[] actor : actors) {
                ps.setString(1, actor[0]);
                ps.setString(2, actor[1]);
                ps.addBatch(); // 添加到批处理队列
            }

            // 执行批处理，返回每条语句影响的行数
            int[] results = ps.executeBatch();
            conn.commit(); // 提交事务

            int totalInserted = 0;
            for (int r : results) {
                totalInserted += r;
            }
            log.info("示例9 批量插入完成，共插入 {} 条", totalInserted);

            // 清理测试数据（可选）
            // DELETE FROM actor WHERE first_name = 'Batch' AND last_name LIKE 'Actor%'

        } catch (SQLException e) {
            log.error("示例9 批量插入失败: {}", e.getMessage(), e);
        } finally {
            // 实际项目中应在此恢复 autoCommit
        }
    }

    // ========================================================================
    // 示例 10: 事务管理 — 手动 COMMIT / ROLLBACK
    // ========================================================================

    /**
     * 示例 10: 事务管理 - 手动控制事务提交和回滚。
     * <p>
     * 模拟场景: 插入一条 payment 记录，同时更新 customer 的最后活动时间。
     * 两步要么全成功，要么全回滚。
     * <p>
     * 关键: conn.setAutoCommit(false) 开启事务；
     *       conn.commit() 提交；
     *       conn.rollback() 回滚。
     */
    public void example10_transaction() {
        try (Connection conn = dataSource.getConnection()) {

            // ===== 步骤 1: 关闭自动提交，开启事务 =====
            conn.setAutoCommit(false);

            try {
                // ===== 步骤 2: 执行业务 SQL =====
                // 2a. 插入一笔支付记录
                String insertPaymentSql = """
                        INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
                        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                        """;
                try (PreparedStatement ps = conn.prepareStatement(insertPaymentSql)) {
                    ps.setInt(1, 1);                          // customer_id
                    ps.setInt(2, 1);                          // staff_id
                    ps.setInt(3, 1);                          // rental_id
                    ps.setBigDecimal(4, new BigDecimal("9.99")); // amount
                    ps.executeUpdate();
                }

                // 2b. 更新客户最后活动时间
                String updateCustomerSql = "UPDATE customer SET last_update = CURRENT_TIMESTAMP WHERE customer_id = ?";
                try (PreparedStatement ps = conn.prepareStatement(updateCustomerSql)) {
                    ps.setInt(1, 1); // customer_id
                    ps.executeUpdate();
                }

                // ===== 步骤 3: 提交事务 =====
                conn.commit();
                log.info("示例10 事务提交成功");

            } catch (SQLException e) {
                // ===== 步骤 4: 发生异常时回滚 =====
                conn.rollback();
                log.error("示例10 事务回滚: {}", e.getMessage(), e);
            }

        } catch (SQLException e) {
            log.error("示例10 获取连接失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 11: 调用存储函数（Stored Function）
    // ========================================================================

    /**
     * 示例 11: 调用存储函数 - 使用 CallableStatement 或 SELECT 方式。
     * <p>
     * Pagila 数据库有 inventory_in_stock(inventory_id) 函数，
     * 返回 BOOLEAN 表示该库存项是否在库。
     * <p>
     * 方式一: SELECT func_name(?, ?) — 最简洁
     * 方式二: {? = CALL func_name(?)} — 标准 JDBC CallableStatement
     */
    public void example11_storedFunction() {
        // 方式一: 直接用 SELECT 调用存储函数
        // language=SQL
        String sql = "SELECT inventory_in_stock(?) AS in_stock";

        try (Connection conn = dataSource.getConnection();
             PreparedStatement ps = conn.prepareStatement(sql)) {

            ps.setInt(1, 1); // inventory_id = 1

            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    boolean inStock = rs.getBoolean("in_stock");
                    log.info("示例11 inventory_id=1 在库状态: {}", inStock ? "在库" : "不在库");
                }
            }

        } catch (SQLException e) {
            log.error("示例11 存储函数调用失败: {}", e.getMessage(), e);
        }
    }

    /**
     * 示例 11b: 使用标准 JDBC CallableStatement 调用存储函数。
     * <p>
     * 语法: {? = CALL function_name(?, ?)}
     * 第一个 ? 是返回值（OUT 参数），后续 ? 是入参。
     */
    public void example11b_callableStatement() {
        // language=SQL
        String callSql = "{? = CALL inventory_in_stock(?)}";

        try (Connection conn = dataSource.getConnection();
             CallableStatement cs = conn.prepareCall(callSql)) {

            // 注册 OUT 参数（返回值）
            cs.registerOutParameter(1, Types.BOOLEAN);
            // 设置 IN 参数
            cs.setInt(2, 1); // inventory_id = 1

            cs.execute();

            boolean inStock = cs.getBoolean(1);
            log.info("示例11b (CallableStatement) inventory_id=1 在库状态: {}", inStock ? "在库" : "不在库");

        } catch (SQLException e) {
            log.error("示例11b CallableStatement 调用失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 12: 原生 DriverManager 连接（不使用连接池）
    // ========================================================================

    /**
     * 示例 12: 使用 DriverManager 直接获取连接（不依赖 Spring/连接池）。
     * <p>
     * 适用场景: 独立 Java 程序、测试工具、无 Spring 环境的脚本。
     * <p>
     * 注意: 生产环境应使用连接池（HikariCP），DriverManager 每次 new 连接开销大。
     */
    public void example12_driverManager() {
        // openGauss JDBC 连接 URL
        // 格式: jdbc:opengauss://host:port/database
        String url = "jdbc:opengauss://localhost:5432/pagila";
        String username = "gaussdb";
        String password = "Enmo@123";

        // 显式加载驱动（Java 6+ 可省略，因为 ServiceLoader 会自动发现）
        // Class.forName("org.opengauss.Driver");

        try (Connection conn = DriverManager.getConnection(url, username, password);
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT current_database(), current_timestamp")) {

            if (rs.next()) {
                log.info("示例12 DriverManager: 数据库={}, 当前时间={}",
                        rs.getString(1), rs.getTimestamp(2));
            }

        } catch (SQLException e) {
            log.error("示例12 DriverManager 连接失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 13: 子查询与 EXISTS
    // ========================================================================

    /**
     * 示例 13: 子查询 - 查询有逾期未还记录（超过租赁期限且未归还）的客户。
     * <p>
     * SQL: 使用子查询 + EXISTS 筛选符合条件的客户。
     */
    public void example13_subquery() {
        // language=SQL
        String sql = """
                SELECT c.customer_id, c.first_name, c.last_name, c.email
                FROM customer c
                WHERE EXISTS (
                    SELECT 1 FROM rental r
                    JOIN inventory i ON r.inventory_id = i.inventory_id
                    JOIN film f ON i.film_id = f.film_id
                    WHERE r.customer_id = c.customer_id
                      AND r.return_date IS NULL
                      AND r.rental_date + (f.rental_duration || ' days')::interval < CURRENT_TIMESTAMP
                )
                LIMIT 10
                """;

        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {

            int count = 0;
            while (rs.next()) {
                count++;
                log.info("示例13 逾期客户: id={}, name={} {}, email={}",
                        rs.getInt("customer_id"),
                        rs.getString("first_name"),
                        rs.getString("last_name"),
                        rs.getString("email"));
            }
            log.info("示例13 共 {} 位逾期客户", count);

        } catch (SQLException e) {
            log.error("示例13 子查询失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 14: GROUP BY + HAVING
    // ========================================================================

    /**
     * 示例 14: GROUP BY + HAVING - 按类别统计电影数量，只显示电影数 > 50 的类别。
     */
    public void example14_groupByHaving() {
        // language=SQL
        String sql = """
                SELECT c.name AS category_name, COUNT(fc.film_id) AS film_count
                FROM category c
                    JOIN film_category fc ON c.category_id = fc.category_id
                GROUP BY c.name
                HAVING COUNT(fc.film_id) > 50
                ORDER BY film_count DESC
                """;

        try (Connection conn = dataSource.getConnection();
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {

            while (rs.next()) {
                log.info("示例14 类别: {} -> {} 部电影",
                        rs.getString("category_name"),
                        rs.getInt("film_count"));
            }

        } catch (SQLException e) {
            log.error("示例14 GROUP BY 查询失败: {}", e.getMessage(), e);
        }
    }

    // ========================================================================
    // 示例 15: DatabaseMetaData — 获取数据库元信息
    // ========================================================================

    /**
     * 示例 15: 获取数据库元信息 - DatabaseMetaData 查看表结构。
     * <p>
     * 通过 Connection.getMetaData() 获取 DatabaseMetaData，
     * 可查询数据库版本、表列表、列信息、主键等。
     */
    public void example15_metadata() {
        try (Connection conn = dataSource.getConnection()) {

            DatabaseMetaData meta = conn.getMetaData();

            log.info("示例15 数据库信息:");
            log.info("  产品名: {}", meta.getDatabaseProductName());
            log.info("  版本: {}", meta.getDatabaseProductVersion());
            log.info("  驱动名: {}", meta.getDriverName());
            log.info("  驱动版本: {}", meta.getDriverVersion());
            log.info("  URL: {}", meta.getURL());
            log.info("  用户名: {}", meta.getUserName());

            // 获取 film 表的列信息
            log.info("  --- film 表列信息 ---");
            try (ResultSet columns = meta.getColumns(null, "public", "film", null)) {
                while (columns.next()) {
                    String colName = columns.getString("COLUMN_NAME");
                    String colType = columns.getString("TYPE_NAME");
                    int colSize = columns.getInt("COLUMN_SIZE");
                    String nullable = columns.getString("IS_NULLABLE");
                    log.info("    {} {} ({}) nullable={}", colName, colType, colSize, nullable);
                }
            }

        } catch (SQLException e) {
            log.error("示例15 元数据查询失败: {}", e.getMessage(), e);
        }
    }
}
