<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Sales Report");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Sales Reports</h2>
        <p>Sales by category and store - Uses RANK() window functions</p>
    </div>

    <div style="display: flex; gap: 20px; flex-wrap: wrap;">

        <!-- Sales by Category -->
        <div class="card" style="flex: 1; min-width: 400px;">
            <h3>Sales by Category</h3>
            <c:if test="${not empty salesByCategory}">
            <table>
                <thead>
                    <tr>
                        <th>Rank</th>
                        <th>Category</th>
                        <th>Rental Count</th>
                        <th>Total Sales</th>
                        <th>Avg Sale</th>
                    </tr>
                </thead>
                <tbody>
                    <c:forEach var="cat" items="${salesByCategory}">
                    <tr>
                        <td><span class="badge badge-info"><c:out value="${cat.rank}"/></span></td>
                        <td><c:out value="${cat.category_name}"/></td>
                        <td><c:out value="${cat.rental_count}"/></td>
                        <td><fmt:formatNumber value="${cat.total_sales}" type="currency" currencySymbol="$"/></td>
                        <td><fmt:formatNumber value="${cat.avg_sale}" type="currency" currencySymbol="$"/></td>
                    </tr>
                    </c:forEach>
                </tbody>
            </table>
            </c:if>
            <c:if test="${empty salesByCategory}">
            <p style="color: #95a5a6;">No sales data available.</p>
            </c:if>
        </div>

        <!-- Sales by Store -->
        <div class="card" style="flex: 1; min-width: 350px;">
            <h3>Sales by Store</h3>
            <c:if test="${not empty salesByStore}">
            <table>
                <thead>
                    <tr>
                        <th>Store ID</th>
                        <th>Address</th>
                        <th>District</th>
                        <th>Transactions</th>
                        <th>Total Sales</th>
                        <th>Avg Transaction</th>
                    </tr>
                </thead>
                <tbody>
                    <c:forEach var="store" items="${salesByStore}">
                    <tr>
                        <td><c:out value="${store.store_id}"/></td>
                        <td><c:out value="${store.address}"/></td>
                        <td><c:out value="${store.district}"/></td>
                        <td><c:out value="${store.transaction_count}"/></td>
                        <td><fmt:formatNumber value="${store.total_sales}" type="currency" currencySymbol="$"/></td>
                        <td><fmt:formatNumber value="${store.avg_transaction}" type="currency" currencySymbol="$"/></td>
                    </tr>
                    </c:forEach>
                </tbody>
            </table>
            </c:if>
            <c:if test="${empty salesByStore}">
            <p style="color: #95a5a6;">No store sales data available.</p>
            </c:if>
        </div>
    </div>
</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Sales Report"/>
</jsp:include>
