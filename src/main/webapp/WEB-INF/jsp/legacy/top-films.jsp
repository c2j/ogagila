<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Top Rented Films");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Top Rented Films</h2>
        <p>Uses RANK() window function results - Shows rental count and rank</p>
    </div>

    <table>
        <thead>
            <tr>
                <th>Rank</th>
                <th>Film ID</th>
                <th>Title</th>
                <th>Rating</th>
                <th>Rental Rate</th>
                <th>Length</th>
                <th>Rental Count</th>
                <th>Total Revenue</th>
            </tr>
        </thead>
        <tbody>
            <c:forEach var="film" items="${topFilms}">
            <tr>
                <td><span class="badge badge-warning"><c:out value="${film.rank}"/></span></td>
                <td><c:out value="${film.film_id}"/></td>
                <td>
                    <a href="${pageContext.request.contextPath}/legacy/films/<c:out value="${film.film_id}"/>">
                        <c:out value="${film.title}"/>
                    </a>
                </td>
                <td><span class="badge badge-info"><c:out value="${film.rating}"/></span></td>
                <td><fmt:formatNumber value="${film.rental_rate}" type="currency" currencySymbol="$"/></td>
                <td><c:out value="${film.length}"/> min</td>
                <td><strong><c:out value="${film.rental_count}"/></strong></td>
                <td><fmt:formatNumber value="${film.total_revenue}" type="currency" currencySymbol="$"/></td>
            </tr>
            </c:forEach>
            <c:if test="${empty topFilms}">
            <tr>
                <td colspan="8" style="text-align:center; padding:30px; color:#95a5a6;">
                    No film data available.
                </td>
            </tr>
            </c:if>
        </tbody>
    </table>
</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Top Rented Films"/>
</jsp:include>
