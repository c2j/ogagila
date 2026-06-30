<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="java.sql.*, javax.sql.*, java.util.*" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Raw SQL Demo");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Raw SQL Rental Statistics</h2>
        <p>GEN1 (Extreme Legacy) - Raw JDBC in JSP (Production since 2008)</p>
    </div>

    <div class="warning-banner">
        &#x26A0;&#xFE0F; LEGACY CODE - DO NOT MODIFY - Raw SQL in JSP (Production since 2008)
    </div>

    <%
        DataSource ds = (DataSource) request.getAttribute("datasource");
        if (ds == null) {
            out.println("<div class='alert alert-danger'>DataSource not available!</div>");
        } else {
            Connection conn = null;
            PreparedStatement stmt = null;
            ResultSet rs = null;
    %>

    <!-- Query 1: Top Customers by Rental Count and Spending -->
    <div class="card">
        <h3>Top 20 Customers by Rental Activity &amp; Spending</h3>
        <p style="font-size:12px; color:#7f8c8d; margin-bottom:10px;">
            SQL: Raw JDBC with GaussDB-specific partition pruning via payment_date range
        </p>
        <table>
            <thead>
                <tr>
                    <th>#</th>
                    <th>Customer Name</th>
                    <th>Rental Count</th>
                    <th>Total Spent</th>
                </tr>
            </thead>
            <tbody>
                <%
                try {
                    conn = ds.getConnection();
                    stmt = conn.prepareStatement(
                        "SELECT c.first_name, c.last_name, COUNT(r.rental_id) as rental_count, " +
                        "SUM(p.amount) as total_spent " +
                        "FROM customer c " +
                        "JOIN rental r ON c.customer_id = r.customer_id " +
                        "JOIN payment p ON r.rental_id = p.rental_id " +
                        "WHERE p.payment_date >= '2022-01-01' " +
                        "GROUP BY c.customer_id, c.first_name, c.last_name " +
                        "ORDER BY total_spent DESC " +
                        "LIMIT 20"
                    );
                    rs = stmt.executeQuery();
                    int rank = 1;
                    while (rs.next()) {
                        String firstName = rs.getString("first_name");
                        String lastName = rs.getString("last_name");
                        int rentalCount = rs.getInt("rental_count");
                        double totalSpent = rs.getDouble("total_spent");
                %>
                <tr>
                    <td><%= rank++ %></td>
                    <td><%= escapeHtml(firstName) %> <%= escapeHtml(lastName) %></td>
                    <td><%= rentalCount %></td>
                    <td><%= String.format("$%.2f", totalSpent) %></td>
                </tr>
                <%
                    }
                } catch (SQLException e) {
                    out.println("<tr><td colspan='4' class='alert alert-danger'>SQL Error: " +
                                escapeHtml(e.getMessage()) + "</td></tr>");
                } finally {
                    if (rs != null) try { rs.close(); } catch (SQLException e) {}
                    if (stmt != null) try { stmt.close(); } catch (SQLException e) {}
                    if (conn != null) try { conn.close(); } catch (SQLException e) {}
                }
                %>
            </tbody>
        </table>
    </div>

    <!-- Query 2: GaussDB CONNECT BY hierarchical store query -->
    <div class="card">
        <h3>Store Hierarchy (GaussDB CONNECT BY)</h3>
        <p style="font-size:12px; color:#7f8c8d; margin-bottom:10px;">
            SQL: Uses GaussDB Oracle-compatible CONNECT BY PRIOR syntax for hierarchical store traversal
        </p>
        <table>
            <thead>
                <tr>
                    <th>Store ID</th>
                    <th>Manager Staff ID</th>
                    <th>Address ID</th>
                    <th>Level</th>
                </tr>
            </thead>
            <tbody>
                <%
                Connection conn2 = null;
                PreparedStatement stmt2 = null;
                ResultSet rs2 = null;
                try {
                    conn2 = ds.getConnection();
                    stmt2 = conn2.prepareStatement(
                        "SELECT store_id, manager_staff_id, address_id, LEVEL " +
                        "FROM store " +
                        "START WITH manager_staff_id IS NOT NULL " +
                        "CONNECT BY PRIOR store_id = manager_staff_id " +
                        "ORDER BY LEVEL, store_id"
                    );
                    rs2 = stmt2.executeQuery();
                    while (rs2.next()) {
                        int storeId = rs2.getInt("store_id");
                        int mgrStaffId = rs2.getInt("manager_staff_id");
                        int addrId = rs2.getInt("address_id");
                        int level = rs2.getInt("LEVEL");
                %>
                <tr>
                    <td><%= storeId %></td>
                    <td><%= mgrStaffId %></td>
                    <td><%= addrId %></td>
                    <td><%= level %></td>
                </tr>
                <%
                    }
                } catch (SQLException e) {
                    out.println("<tr><td colspan='4' class='alert alert-danger'>SQL Error: " +
                                escapeHtml(e.getMessage()) + "</td></tr>");
                } finally {
                    if (rs2 != null) try { rs2.close(); } catch (SQLException e) {}
                    if (stmt2 != null) try { stmt2.close(); } catch (SQLException e) {}
                    if (conn2 != null) try { conn2.close(); } catch (SQLException e) {}
                }
                %>
            </tbody>
        </table>
    </div>

    <!-- Query 3: Inventory In Stock stored procedure -->
    <div class="card">
        <h3>Film Inventory Stock Status (Stored Procedure)</h3>
        <p style="font-size:12px; color:#7f8c8d; margin-bottom:10px;">
            SQL: Calls inventory_in_stock(?) stored function via raw JDBC
        </p>
        <table>
            <thead>
                <tr>
                    <th>Inventory ID</th>
                    <th>In Stock?</th>
                </tr>
            </thead>
            <tbody>
                <%
                Connection conn3 = null;
                PreparedStatement stmt3 = null;
                ResultSet rs3 = null;
                try {
                    conn3 = ds.getConnection();
                    stmt3 = conn3.prepareStatement(
                        "SELECT i.inventory_id, inventory_in_stock(i.inventory_id) AS in_stock " +
                        "FROM inventory i " +
                        "WHERE i.inventory_id <= 10 " +
                        "ORDER BY i.inventory_id"
                    );
                    rs3 = stmt3.executeQuery();
                    while (rs3.next()) {
                        int invId = rs3.getInt("inventory_id");
                        boolean inStock = rs3.getBoolean("in_stock");
                %>
                <tr>
                    <td><%= invId %></td>
                    <td>
                        <% if (inStock) { %>
                            <span class="badge badge-success">In Stock</span>
                        <% } else { %>
                            <span class="badge badge-danger">Out of Stock</span>
                        <% } %>
                    </td>
                </tr>
                <%
                    }
                } catch (SQLException e) {
                    out.println("<tr><td colspan='2' class='alert alert-danger'>SQL Error: " +
                                escapeHtml(e.getMessage()) + "</td></tr>");
                } finally {
                    if (rs3 != null) try { rs3.close(); } catch (SQLException e) {}
                    if (stmt3 != null) try { stmt3.close(); } catch (SQLException e) {}
                    if (conn3 != null) try { conn3.close(); } catch (SQLException e) {}
                }
                %>
            </tbody>
        </table>
    </div>

    <%
        } // end if datasource != null
    %>

    <div style="margin-top:20px;">
        <div class="alert alert-warning">
            <strong>&#x26A0;&#xFE0F; Legacy Pattern Warning:</strong> This page demonstrates the GEN1 pattern where
            database connections, SQL queries, and HTML rendering are all mixed in a single JSP file.
            This code has no unit tests, no transaction management, and no connection pooling safety checks.
            It exists here to show the evolution of the codebase from 2008 to present day.
        </div>
    </div>
</div>

<%!
    private String escapeHtml(String input) {
        if (input == null) return "";
        return input.replace("&", "&amp;")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;")
                    .replace("\"", "&quot;")
                    .replace("'", "&#39;");
    }
%>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Raw SQL Rental Stats"/>
</jsp:include>
