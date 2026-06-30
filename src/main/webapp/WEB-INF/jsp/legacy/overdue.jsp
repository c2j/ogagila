<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%@ page import="java.time.LocalDateTime, java.time.temporal.ChronoUnit" %>
<%
    request.setAttribute("param.pageTitle", "Overdue Rentals");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Overdue Rentals</h2>
        <p>GaussDB-specific: uses film.rental_duration and interval arithmetic</p>
    </div>

    <div class="alert alert-danger">
        <strong>Attention!</strong> These rentals are overdue. The query uses GaussDB interval arithmetic:
        <code>rental_date + (rental_duration || ' days')::INTERVAL &lt; now()</code>
    </div>

    <%!
        private long daysBetween(LocalDateTime from) {
            if (from == null) return 0;
            return ChronoUnit.DAYS.between(from, LocalDateTime.now());
        }
    %>

    <table>
        <thead>
            <tr>
                <th>Rental ID</th>
                <th>Rental Date</th>
                <th>Customer ID</th>
                <th>Inventory ID</th>
                <th>Days Since Rental</th>
                <th>Status</th>
            </tr>
        </thead>
        <tbody>
            <c:forEach var="rental" items="${overdueRentals}">
            <%
                LocalDateTime rDate = ((com.ogagila.entity.Rental) pageContext.getAttribute("rental")).getRentalDate();
                long days = daysBetween(rDate);
                pageContext.setAttribute("_days", days);
            %>
            <tr class="overdue">
                <td><c:out value="${rental.rentalId}"/></td>
                <td><c:out value="${rental.rentalDate}"/></td>
                <td><a href="${pageContext.request.contextPath}/legacy/customers/<c:out value="${rental.customerId}"/>" style="color:#c0392b;">
                    <c:out value="${rental.customerId}"/></a></td>
                <td><c:out value="${rental.inventoryId}"/></td>
                <td><c:out value="${_days}"/> days</td>
                <td><span class="badge badge-danger">OVERDUE</span></td>
            </tr>
            </c:forEach>
            <c:if test="${empty overdueRentals}">
            <tr>
                <td colspan="6" style="text-align:center; padding:30px; color:#27ae60;">
                    <strong>No overdue rentals! All rentals are on time.</strong>
                </td>
            </tr>
            </c:if>
        </tbody>
    </table>

    <div style="margin-top: 20px;">
        <a href="${pageContext.request.contextPath}/legacy/rentals" class="btn btn-default">&laquo; Back to Rentals</a>
    </div>
</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Overdue Rentals"/>
</jsp:include>
