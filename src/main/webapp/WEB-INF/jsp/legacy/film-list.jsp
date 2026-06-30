<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Film List");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Film Management</h2>
        <p>Browse and search films - Generation 2 (MyBatis + JSP)</p>
    </div>

    <!-- Search Form -->
    <div class="search-form">
        <form action="${pageContext.request.contextPath}/legacy/films/search" method="get" style="display: flex; gap: 10px; align-items: center;">
            <input type="text" name="keyword" placeholder="Search films by keyword (fulltext search)..." value="<c:out value="${keyword}"/>"/>
            <button type="submit" class="btn btn-primary">Search</button>
            <c:if test="${not empty keyword}">
                <a href="${pageContext.request.contextPath}/legacy/films" class="btn btn-default">Clear</a>
            </c:if>
        </form>
    </div>

    <!-- Film Table -->
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Title</th>
                <th>Rating</th>
                <th>Length</th>
                <th>Rental Rate</th>
                <th>Rental Duration</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
            <c:forEach var="film" items="${films.list}">
            <tr>
                <td><c:out value="${film.filmId}"/></td>
                <td><c:out value="${film.title}"/></td>
                <td><span class="badge badge-info"><c:out value="${film.rating}"/></span></td>
                <td><c:out value="${film.length}"/> min</td>
                <td><fmt:formatNumber value="${film.rentalRate}" type="currency" currencySymbol="$"/></td>
                <td><c:out value="${film.rentalDuration}"/> days</td>
                <td>
                    <a href="${pageContext.request.contextPath}/legacy/films/<c:out value="${film.filmId}"/>" class="btn btn-primary btn-sm">Detail</a>
                </td>
            </tr>
            </c:forEach>
            <c:if test="${empty films.list}">
            <tr>
                <td colspan="7" style="text-align:center; padding:30px; color:#95a5a6;">
                    No films found.
                    <c:if test="${not empty keyword}">
                        Try a different search keyword.
                    </c:if>
                </td>
            </tr>
            </c:if>
        </tbody>
    </table>

    <!-- Pagination -->
    <c:if test="${films.totalPages > 1}">
    <div class="pagination">
        <c:if test="${page > 1}">
            <a href="${pageContext.request.contextPath}/legacy/films?page=${page - 1}&size=${size}">&laquo; Prev</a>
        </c:if>
        <c:forEach var="i" begin="1" end="${films.totalPages}">
            <c:if test="${i >= page - 2 && i <= page + 2}">
                <a href="${pageContext.request.contextPath}/legacy/films?page=${i}&size=${size}"
                   class="${i == page ? 'active' : ''}"><c:out value="${i}"/></a>
            </c:if>
        </c:forEach>
        <c:if test="${page < films.totalPages}">
            <a href="${pageContext.request.contextPath}/legacy/films?page=${page + 1}&size=${size}">Next &raquo;</a>
        </c:if>
    </div>
    </c:if>

    <div style="margin-top: 10px; text-align: right; color: #7f8c8d; font-size: 12px;">
        Total films: <strong><c:out value="${films.total}"/></strong>
    </div>
</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Film List"/>
</jsp:include>
