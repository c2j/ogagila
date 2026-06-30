<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Rental List");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Rental Management</h2>
        <p>Recent rentals - Generation 2 (MyBatis + JSP)</p>
    </div>

    <!-- Filters -->
    <div class="search-form">
        <form method="get" action="${pageContext.request.contextPath}/legacy/rentals" style="display: flex; gap: 10px; align-items: center; flex-wrap: wrap;">
            <label style="font-size:13px; color:#2c3e50;">Date Filter:</label>
            <input type="date" name="dateFrom" style="padding:7px; border:1px solid #bdc3c7; border-radius:3px; font-size:13px;"/>
            <input type="date" name="dateTo" style="padding:7px; border:1px solid #bdc3c7; border-radius:3px; font-size:13px;"/>
            <button type="submit" class="btn btn-primary btn-sm">Filter</button>
            <a href="${pageContext.request.contextPath}/legacy/rentals" class="btn btn-default btn-sm">Clear</a>
            <a href="${pageContext.request.contextPath}/legacy/rentals/overdue" class="btn btn-danger btn-sm" style="margin-left:auto;">View Overdue</a>
        </form>
    </div>

    <!-- Rental Table -->
    <table>
        <thead>
            <tr>
                <th>Rental ID</th>
                <th>Rental Date</th>
                <th>Inventory ID</th>
                <th>Customer ID</th>
                <th>Return Date</th>
                <th>Staff ID</th>
                <th>Status</th>
            </tr>
        </thead>
        <tbody>
            <c:forEach var="rental" items="${rentals.list}">
            <tr class="${rental.returnDate == null ? 'overdue' : ''}">
                <td><c:out value="${rental.rentalId}"/></td>
                <td><c:out value="${rental.rentalDate}"/></td>
                <td><c:out value="${rental.inventoryId}"/></td>
                <td><a href="${pageContext.request.contextPath}/legacy/customers/<c:out value="${rental.customerId}"/>"><c:out value="${rental.customerId}"/></a></td>
                <td>
                    <c:if test="${rental.returnDate != null}">
                        <c:out value="${rental.returnDate}"/>
                    </c:if>
                    <c:if test="${rental.returnDate == null}">
                        <span class="badge badge-danger">NOT RETURNED</span>
                    </c:if>
                </td>
                <td><c:out value="${rental.staffId}"/></td>
                <td>
                    <c:choose>
                        <c:when test="${rental.returnDate == null}">
                            <span class="badge badge-warning">Active</span>
                        </c:when>
                        <c:otherwise>
                            <span class="badge badge-success">Returned</span>
                        </c:otherwise>
                    </c:choose>
                </td>
            </tr>
            </c:forEach>
            <c:if test="${empty rentals.list}">
            <tr>
                <td colspan="7" style="text-align:center; padding:30px; color:#95a5a6;">
                    No rentals found.
                </td>
            </tr>
            </c:if>
        </tbody>
    </table>

    <!-- Pagination -->
    <c:if test="${rentals.totalPages > 1}">
    <div class="pagination">
        <c:if test="${page > 1}">
            <a href="${pageContext.request.contextPath}/legacy/rentals?page=${page - 1}&size=${size}">&laquo; Prev</a>
        </c:if>
        <c:forEach var="i" begin="1" end="${rentals.totalPages}">
            <c:if test="${i >= page - 2 && i <= page + 2}">
                <a href="${pageContext.request.contextPath}/legacy/rentals?page=${i}&size=${size}"
                   class="${i == page ? 'active' : ''}"><c:out value="${i}"/></a>
            </c:if>
        </c:forEach>
        <c:if test="${page < rentals.totalPages}">
            <a href="${pageContext.request.contextPath}/legacy/rentals?page=${page + 1}&size=${size}">Next &raquo;</a>
        </c:if>
    </div>
    </c:if>

    <div style="margin-top: 10px; text-align: right; color: #7f8c8d; font-size: 12px;">
        Total rentals: <strong><c:out value="${rentals.total}"/></strong>
    </div>
</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Rental List"/>
</jsp:include>
