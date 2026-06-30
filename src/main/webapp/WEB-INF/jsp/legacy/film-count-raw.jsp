<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="java.sql.*, javax.sql.*" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Film Count Raw");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Film Count (Raw JDBC)</h2>
        <p>GEN1 (Extreme Legacy) - Simple COUNT(*) via raw JDBC</p>
    </div>

    <div class="warning-banner">
        &#x26A0;&#xFE0F; This page was built in 2005 and has 0 unit tests
    </div>

    <%
        DataSource ds = (DataSource) request.getAttribute("datasource");
        if (ds == null) {
            out.println("<div class='alert alert-danger'>DataSource not available!</div>");
        } else {
            Connection conn = null;
            PreparedStatement stmt = null;
            ResultSet rs = null;
            long filmCount = 0;
            long customerCount = 0;
            long actorCount = 0;
            long categoryCount = 0;
            long languageCount = 0;
            long storeCount = 0;
            long inventoryCount = 0;
            String errorMsg = null;

            try {
                conn = ds.getConnection();

                stmt = conn.prepareStatement("SELECT COUNT(*) FROM film");
                rs = stmt.executeQuery();
                if (rs.next()) filmCount = rs.getLong(1);
                rs.close(); stmt.close();

                stmt = conn.prepareStatement("SELECT COUNT(*) FROM customer");
                rs = stmt.executeQuery();
                if (rs.next()) customerCount = rs.getLong(1);
                rs.close(); stmt.close();

                stmt = conn.prepareStatement("SELECT COUNT(*) FROM actor");
                rs = stmt.executeQuery();
                if (rs.next()) actorCount = rs.getLong(1);
                rs.close(); stmt.close();

                stmt = conn.prepareStatement("SELECT COUNT(*) FROM category");
                rs = stmt.executeQuery();
                if (rs.next()) categoryCount = rs.getLong(1);
                rs.close(); stmt.close();

                stmt = conn.prepareStatement("SELECT COUNT(*) FROM language");
                rs = stmt.executeQuery();
                if (rs.next()) languageCount = rs.getLong(1);
                rs.close(); stmt.close();

                stmt = conn.prepareStatement("SELECT COUNT(*) FROM store");
                rs = stmt.executeQuery();
                if (rs.next()) storeCount = rs.getLong(1);
                rs.close(); stmt.close();

                stmt = conn.prepareStatement("SELECT COUNT(*) FROM inventory");
                rs = stmt.executeQuery();
                if (rs.next()) inventoryCount = rs.getLong(1);
                rs.close(); stmt.close();

            } catch (SQLException e) {
                errorMsg = e.getMessage();
            } finally {
                if (rs != null) try { rs.close(); } catch (SQLException e) {}
                if (stmt != null) try { stmt.close(); } catch (SQLException e) {}
                if (conn != null) try { conn.close(); } catch (SQLException e) {}
            }

            if (errorMsg != null) {
    %>
                <div class="alert alert-danger">Database Error: <%= escapeHtml(errorMsg) %></div>
    <%
            } else {
    %>

    <!-- Display counts from raw JDBC -->
    <div style="margin-bottom: 20px;">
        <div class="stat-box">
            <div class="stat-label">Films</div>
            <div class="stat-value"><%= filmCount %></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Customers</div>
            <div class="stat-value"><%= customerCount %></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Actors</div>
            <div class="stat-value"><%= actorCount %></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Categories</div>
            <div class="stat-value"><%= categoryCount %></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Languages</div>
            <div class="stat-value"><%= languageCount %></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Stores</div>
            <div class="stat-value"><%= storeCount %></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Inventory Items</div>
            <div class="stat-value"><%= inventoryCount %></div>
        </div>
    </div>

    <!-- Raw SQL Queries Display -->
    <div class="card">
        <h3>Raw SQL Queries Executed</h3>
        <p style="font-size:12px; color:#7f8c8d;">The following SQL was executed directly in this JSP via raw JDBC:</p>
        <pre style="background:#f8f9fa; padding:15px; border:1px solid #ecf0f1; border-radius:3px; margin-top:10px; overflow-x:auto; font-size:12px;">
SELECT COUNT(*) FROM film
SELECT COUNT(*) FROM customer
SELECT COUNT(*) FROM actor
SELECT COUNT(*) FROM category
SELECT COUNT(*) FROM language
SELECT COUNT(*) FROM store
SELECT COUNT(*) FROM inventory
        </pre>
    </div>

    <div class="alert alert-danger" style="margin-top:20px;">
        <strong>&#x26A0;&#xFE0F; This page was built in 2005 and has 0 unit tests.</strong>
        All SQL is embedded directly in JSP scriptlets. No MyBatis, no service layer,
        no connection pooling safety. This represents the GEN1 legacy pattern that
        the project started with before migrating to MyBatis (GEN2) and Vue (GEN3).
    </div>

    <%
            } // end if no error
        } // end if datasource != null
    %>
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
    <jsp:param name="pageName" value="Film Count Raw"/>
</jsp:include>
