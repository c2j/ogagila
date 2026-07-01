<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="com.ogagila.example.jdbc.dao.*, com.ogagila.example.jdbc.dao.FilmJdbcDao.*" %>
<%@ page import="java.sql.*, javax.sql.*, java.util.*" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Film DAO Demo");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Film List (JSP + Java DAO)</h2>
        <p>GEN1.5 — JSP references Java DAO classes instead of writing raw SQL</p>
    </div>

    <div class="warning-banner">
        GEN1.5 Pattern: JSP imports and calls Java DAO classes (FilmJdbcDao, ActorJdbcDao).
        SQL is encapsulated in DAO — JSP only renders data.
    </div>

    <%
        // ============================================================
        // JSP 从 request 获取 DataSource，然后自己创建 DAO 实例
        // 这是 "JSP 引用 Java 类 DAO" 的核心：
        //   import com.ogagila.example.jdbc.dao.FilmJdbcDao;
        //   FilmJdbcDao dao = new FilmJdbcDao(datasource);
        //   List<FilmJdbcDao.FilmRow> films = dao.findAll(page, pageSize);
        // ============================================================
        DataSource ds = (DataSource) request.getAttribute("datasource");
        int currentPage = (Integer) request.getAttribute("currentPage");
        int pageSize = (Integer) request.getAttribute("pageSize");

        if (ds == null) {
            out.println("<div class='alert alert-danger'>DataSource not available!</div>");
        } else {
            // ---- 步骤 1: 创建 FilmJdbcDao 实例 ----
            FilmJdbcDao filmDao = new FilmJdbcDao(ds);

            // ---- 步骤 2: 调用 DAO 方法获取数据 ----
            List<FilmJdbcDao.FilmRow> films = null;
            long totalFilms = 0;
            List<FilmJdbcDao.RatingCount> ratingStats = null;
            String errorMsg = null;

            try {
                films = filmDao.findAll(currentPage, pageSize);
                totalFilms = filmDao.count();
                ratingStats = filmDao.countByRating();
            } catch (SQLException e) {
                errorMsg = e.getMessage();
            }

            long totalPages = (totalFilms + pageSize - 1) / pageSize;
    %>

    <% if (errorMsg != null) { %>
        <div class="alert alert-danger">DAO Error: <%= errorMsg %></div>
    <% } else { %>

    <!-- DAO 技术栈说明 -->
    <div class="card" style="background: #f0f7ff; border-left: 4px solid #3498db;">
        <h3 style="color:#3498db;">How JSP calls the DAO</h3>
        <pre style="background:#fff; padding:15px; font-size:12px; border:1px solid #d1ecf1;">
&lt;%@ page import="com.ogagila.example.jdbc.dao.FilmJdbcDao" %&gt;
&lt;%
    DataSource ds = (DataSource) request.getAttribute("datasource");
    FilmJdbcDao filmDao = new FilmJdbcDao(ds);
    List&lt;FilmJdbcDao.FilmRow&gt; films = filmDao.findAll(page, pageSize);
    long total = filmDao.count();
%&gt;
        </pre>
    </div>

    <!-- 评级统计卡片 -->
    <div style="margin-bottom: 20px;">
        <% for (FilmJdbcDao.RatingCount rc : ratingStats) { %>
        <div class="stat-box">
            <div class="stat-label"><%= rc.rating != null ? rc.rating : "Unrated" %></div>
            <div class="stat-value"><%= rc.count %></div>
        </div>
        <% } %>
    </div>

    <!-- 电影表格 — 通过 scriptlet 遍历 DAO 返回的数据 -->
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Title</th>
                <th>Year</th>
                <th>Rating</th>
                <th>Length</th>
                <th>Rate</th>
                <th>Days</th>
                <th>Detail</th>
            </tr>
        </thead>
        <tbody>
            <% for (FilmJdbcDao.FilmRow f : films) { %>
            <tr>
                <td><%= f.filmId %></td>
                <td><%= escapeHtml(f.title) %></td>
                <td><%= f.releaseYear != null ? f.releaseYear : "-" %></td>
                <td><span class="badge badge-info"><%= f.rating != null ? f.rating : "-" %></span></td>
                <td><%= f.length != null ? f.length + " min" : "-" %></td>
                <td><%= f.rentalRate != null ? String.format("$%.2f", f.rentalRate) : "-" %></td>
                <td><%= f.rentalDuration != null ? f.rentalDuration + " days" : "-" %></td>
                <td>
                    <a href="${pageContext.request.contextPath}/legacy/dao-demo/films/detail?filmId=<%= f.filmId %>" class="btn btn-primary btn-sm">View</a>
                </td>
            </tr>
            <% } %>
            <% if (films.isEmpty()) { %>
            <tr><td colspan="8" style="text-align:center; padding:30px; color:#95a5a6;">No films found.</td></tr>
            <% } %>
        </tbody>
    </table>

    <!-- 分页 — scriptlet 计算链接 -->
    <div class="pagination">
        <%
        String ctxPath = request.getContextPath();
        String baseUrl = ctxPath + "/legacy/dao-demo/films?pageSize=" + pageSize;
        if (currentPage > 1) {
            out.println("<a href='" + baseUrl + "&page=" + (currentPage - 1) + "'>&laquo; Prev</a>");
        }
        for (int i = 1; i <= totalPages; i++) {
            if (i >= currentPage - 2 && i <= currentPage + 2) {
                String activeClass = (i == currentPage) ? " class='active'" : "";
                out.println("<a href='" + baseUrl + "&page=" + i + "'" + activeClass + ">" + i + "</a>");
            }
        }
        if (currentPage < totalPages) {
            out.println("<a href='" + baseUrl + "&page=" + (currentPage + 1) + "'>Next &raquo;</a>");
        }
        %>
    </div>

    <div style="margin-top: 10px; text-align: right; color: #7f8c8d; font-size: 12px;">
        Total films: <strong><%= totalFilms %></strong> |
        Page <%= currentPage %> of <%= totalPages %> |
        DAO calls: <code>filmDao.findAll(page, pageSize)</code> + <code>filmDao.count()</code> + <code>filmDao.countByRating()</code>
    </div>

    <% } // end if no error %>

    <% } // end if datasource != null %>
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
    <jsp:param name="pageName" value="Film DAO Demo"/>
</jsp:include>
