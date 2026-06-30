<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Customer List");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Customer Management</h2>
        <p>Browse customer records - Generation 2 (MyBatis + JSP)</p>
    </div>

    <!-- Customer Table -->
    <table>
        <thead>
            <tr>
                <th>ID</th>
                <th>Name</th>
                <th>Email</th>
                <th>Active</th>
                <th>Created</th>
                <th>Actions</th>
            </tr>
        </thead>
        <tbody>
            <c:forEach var="customer" items="${customers.list}">
            <tr>
                <td><c:out value="${customer.customerId}"/></td>
                <td><c:out value="${customer.firstName}"/> <c:out value="${customer.lastName}"/></td>
                <td><a href="mailto:<c:out value="${customer.email}"/>"><c:out value="${customer.email}"/></a></td>
                <td>
                    <c:choose>
                        <c:when test="${customer.activebool}">
                            <span class="badge badge-success">Active</span>
                        </c:when>
                        <c:otherwise>
                            <span class="badge badge-danger">Inactive</span>
                        </c:otherwise>
                    </c:choose>
                </td>
                <td><c:out value="${customer.createDate}"/></td>
                <td>
                    <a href="${pageContext.request.contextPath}/legacy/customers/<c:out value="${customer.customerId}"/>" class="btn btn-primary btn-sm">Detail</a>
                </td>
            </tr>
            </c:forEach>
            <c:if test="${empty customers.list}">
            <tr>
                <td colspan="6" style="text-align:center; padding:30px; color:#95a5a6;">
                    No customers found.
                </td>
            </tr>
            </c:if>
        </tbody>
    </table>

    <!-- Pagination -->
    <c:if test="${customers.totalPages > 1}">
    <div class="pagination">
        <c:if test="${page > 1}">
            <a href="${pageContext.request.contextPath}/legacy/customers?page=${page - 1}&size=${size}">&laquo; Prev</a>
        </c:if>
        <c:forEach var="i" begin="1" end="${customers.totalPages}">
            <c:if test="${i >= page - 2 && i <= page + 2}">
                <a href="${pageContext.request.contextPath}/legacy/customers?page=${i}&size=${size}"
                   class="${i == page ? 'active' : ''}"><c:out value="${i}"/></a>
            </c:if>
        </c:forEach>
        <c:if test="${page < customers.totalPages}">
            <a href="${pageContext.request.contextPath}/legacy/customers?page=${page + 1}&size=${size}">Next &raquo;</a>
        </c:if>
    </div>
    </c:if>

    <div style="margin-top: 10px; text-align: right; color: #7f8c8d; font-size: 12px;">
        Total customers: <strong><c:out value="${customers.total}"/></strong>
    </div>
</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Customer List"/>
</jsp:include>
