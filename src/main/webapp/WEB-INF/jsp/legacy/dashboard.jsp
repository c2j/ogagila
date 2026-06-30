<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Dashboard");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>OGAGILA Management System (Legacy Console)</h2>
        <p>System overview dashboard - Generation 2 (MyBatis + JSP)</p>
    </div>

    <!-- Quick Statistics -->
    <div style="margin-bottom: 20px;">
        <div class="stat-box">
            <div class="stat-label">Total Films</div>
            <div class="stat-value"><c:out value="${dashboard.filmCount}"/></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Total Customers</div>
            <div class="stat-value"><c:out value="${dashboard.customerCount}"/></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Total Rentals</div>
            <div class="stat-value"><c:out value="${dashboard.rentalCount}"/></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Total Revenue</div>
            <div class="stat-value"><fmt:formatNumber value="${dashboard.totalRevenue}" type="currency" currencySymbol="$"/></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Overdue Rentals</div>
            <div class="stat-value" style="color: ${dashboard.overdueCount > 0 ? '#e74c3c' : '#27ae60'};">
                <c:out value="${dashboard.overdueCount}"/>
            </div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Actors</div>
            <div class="stat-value"><c:out value="${dashboard.actorCount}"/></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Inventory Items</div>
            <div class="stat-value"><c:out value="${dashboard.inventoryCount}"/></div>
        </div>
        <div class="stat-box">
            <div class="stat-label">Stores</div>
            <div class="stat-value"><c:out value="${dashboard.storeCount}"/></div>
        </div>
    </div>

    <div style="display: flex; gap: 20px; flex-wrap: wrap;">
        <!-- Quick Links -->
        <div class="card" style="flex: 1; min-width: 300px;">
            <h3>Management Console</h3>
            <table>
                <tr><td><a href="${pageContext.request.contextPath}/legacy/films">Film Management</a></td><td><span class="badge badge-info">GEN2</span></td></tr>
                <tr><td><a href="${pageContext.request.contextPath}/legacy/customers">Customer Management</a></td><td><span class="badge badge-info">GEN2</span></td></tr>
                <tr><td><a href="${pageContext.request.contextPath}/legacy/rentals">Rental Management</a></td><td><span class="badge badge-info">GEN2</span></td></tr>
                <tr><td><a href="${pageContext.request.contextPath}/legacy/rentals/overdue">Overdue Rentals</a></td><td><span class="badge badge-danger">GaussDB</span></td></tr>
                <tr><td><a href="${pageContext.request.contextPath}/legacy/reports/sales">Sales Reports</a></td><td><span class="badge badge-info">GEN2</span></td></tr>
                <tr><td><a href="${pageContext.request.contextPath}/legacy/reports/top-films">Top Rented Films</a></td><td><span class="badge badge-info">GEN2</span></td></tr>
                <tr><td><a href="${pageContext.request.contextPath}/legacy/raw-sql/rental-stats">Raw SQL Demo (GEN1)</a></td><td><span class="badge badge-warning">GEN1</span></td></tr>
                <tr><td><a href="${pageContext.request.contextPath}/legacy/raw-sql/film-count">Film Count (GEN1)</a></td><td><span class="badge badge-warning">GEN1</span></td></tr>
                <tr><td><a href="${pageContext.request.contextPath}/modern/film-catalog">Vue Film Catalog</a></td><td><span class="badge badge-success">Vue 3</span></td></tr>
                <tr><td><a href="${pageContext.request.contextPath}/modern/customer-search">Vue Customer Search</a></td><td><span class="badge badge-success">Vue 3</span></td></tr>
            </table>
        </div>

        <!-- Top Films -->
        <div class="card" style="flex: 1; min-width: 300px;">
            <h3>Top Rented Films</h3>
            <table>
                <tr><th>#</th><th>Title</th><th>Rentals</th></tr>
                <c:forEach var="film" items="${dashboard.topFilms}" varStatus="loop">
                <tr>
                    <td><c:out value="${loop.index + 1}"/></td>
                    <td><c:out value="${film.title}"/></td>
                    <td><c:out value="${film.rental_count}"/></td>
                </tr>
                </c:forEach>
                <c:if test="${empty dashboard.topFilms}">
                <tr><td colspan="3" style="text-align:center; color:#95a5a6;">No data available</td></tr>
                </c:if>
            </table>
        </div>

        <!-- Sales by Category -->
        <div class="card" style="flex: 1; min-width: 300px;">
            <h3>Sales by Category</h3>
            <table>
                <tr><th>Category</th><th>Sales</th><th>Rank</th></tr>
                <c:forEach var="cat" items="${salesByCategory}">
                <tr>
                    <td><c:out value="${cat.category_name}"/></td>
                    <td><fmt:formatNumber value="${cat.total_sales}" type="currency" currencySymbol="$"/></td>
                    <td><c:out value="${cat.rank}"/></td>
                </tr>
                </c:forEach>
                <c:if test="${empty salesByCategory}">
                <tr><td colspan="3" style="text-align:center; color:#95a5a6;">No data available</td></tr>
                </c:if>
            </table>
        </div>
    </div>
</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Legacy Dashboard"/>
</jsp:include>
