<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ page import="com.ogagila.example.jdbc.dao.*, com.ogagila.example.jdbc.dao.FilmJdbcDao.*, com.ogagila.example.jdbc.dao.ActorJdbcDao.*" %>
<%@ page import="java.sql.*, javax.sql.*, java.util.*" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Film Detail (DAO)");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Film Detail (JSP + Java DAO)</h2>
        <p>GEN1.5 — JSP calls multiple DAOs on one page: FilmDao + ActorDao</p>
    </div>

    <%
        // ============================================================
        // JSP 在一个页面中调用两个不同的 DAO：FilmJdbcDao 和 ActorJdbcDao
        // ============================================================
        DataSource ds = (DataSource) request.getAttribute("datasource");
        int filmId = (Integer) request.getAttribute("filmId");

        if (ds == null) {
            out.println("<div class='alert alert-danger'>DataSource not available!</div>");
        } else {
            // 创建两个 DAO 实例
            FilmJdbcDao filmDao = new FilmJdbcDao(ds);
            ActorJdbcDao actorDao = new ActorJdbcDao(ds);

            FilmJdbcDao.FilmRow film = null;
            List<ActorJdbcDao.ActorRow> actors = null;
            String errorMsg = null;

            try {
                // 调用 FilmDao 获取电影详情
                film = filmDao.findById(filmId);
                // 调用 ActorDao 获取演员列表
                actors = actorDao.findByFilmId(filmId);
            } catch (SQLException e) {
                errorMsg = e.getMessage();
            }
    %>

    <% if (errorMsg != null) { %>
        <div class="alert alert-danger">DAO Error: <%= errorMsg %></div>
    <% } else if (film == null) { %>
        <div class="alert alert-warning">Film not found: ID <%= filmId %></div>
    <% } else { %>

    <!-- DAO 调用说明 -->
    <div class="card" style="background: #f0f7ff; border-left: 4px solid #3498db; margin-bottom: 20px;">
        <h3 style="color:#3498db;">How JSP calls TWO DAOs on this page</h3>
        <pre style="background:#fff; padding:15px; font-size:12px; border:1px solid #d1ecf1;">
&lt;%@ page import="com.ogagila.example.jdbc.dao.*" %&gt;
&lt;%
    FilmJdbcDao filmDao = new FilmJdbcDao(datasource);
    ActorJdbcDao actorDao = new ActorJdbcDao(datasource);

    FilmJdbcDao.FilmRow film = filmDao.findById(filmId);
    List&lt;ActorJdbcDao.ActorRow&gt; actors = actorDao.findByFilmId(filmId);
%&gt;
        </pre>
    </div>

    <!-- 电影详情卡片 -->
    <div class="card">
        <h3><%= escapeHtml(film.title) %></h3>
        <div class="info-row">
            <div class="label">Film ID</div>
            <div class="value"><%= film.filmId %></div>
        </div>
        <div class="info-row">
            <div class="label">Release Year</div>
            <div class="value"><%= film.releaseYear != null ? film.releaseYear : "-" %></div>
        </div>
        <div class="info-row">
            <div class="label">Rating</div>
            <div class="value"><span class="badge badge-info"><%= film.rating != null ? film.rating : "-" %></span></div>
        </div>
        <div class="info-row">
            <div class="label">Length</div>
            <div class="value"><%= film.length != null ? film.length + " min" : "-" %></div>
        </div>
        <div class="info-row">
            <div class="label">Rental Rate</div>
            <div class="value"><%= film.rentalRate != null ? String.format("$%.2f", film.rentalRate) : "-" %></div>
        </div>
        <div class="info-row">
            <div class="label">Rental Duration</div>
            <div class="value"><%= film.rentalDuration != null ? film.rentalDuration + " days" : "-" %></div>
        </div>
        <div class="info-row">
            <div class="label">Replacement Cost</div>
            <div class="value"><%= film.replacementCost != null ? String.format("$%.2f", film.replacementCost) : "-" %></div>
        </div>
        <div class="info-row">
            <div class="label">Description</div>
            <div class="value"><%= film.description != null ? escapeHtml(film.description) : "-" %></div>
        </div>
    </div>

    <!-- 演员列表 — 来自 ActorDao -->
    <div class="card">
        <h3>Cast (<%= actors != null ? actors.size() : 0 %> actors)</h3>
        <p style="font-size:12px; color:#7f8c8d; margin-bottom:10px;">
            Data from: <code>actorDao.findByFilmId(<%= filmId %>)</code>
        </p>
        <table>
            <thead>
                <tr>
                    <th>Actor ID</th>
                    <th>First Name</th>
                    <th>Last Name</th>
                </tr>
            </thead>
            <tbody>
                <% if (actors != null) {
                    for (ActorJdbcDao.ActorRow a : actors) { %>
                <tr>
                    <td><%= a.actorId %></td>
                    <td><%= escapeHtml(a.firstName) %></td>
                    <td><%= escapeHtml(a.lastName) %></td>
                </tr>
                <%  }
                   } %>
                <% if (actors == null || actors.isEmpty()) { %>
                <tr><td colspan="3" style="text-align:center; color:#95a5a6;">No cast information available.</td></tr>
                <% } %>
            </tbody>
        </table>
    </div>

    <% } // end if film found %>

    <div style="margin-top:20px;">
        <a href="${pageContext.request.contextPath}/legacy/dao-demo/films" class="btn btn-default">&larr; Back to Film List</a>
    </div>

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
    <jsp:param name="pageName" value="Film Detail DAO Demo"/>
</jsp:include>
