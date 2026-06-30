<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Customer Detail");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Customer Detail</h2>
        <p><a href="${pageContext.request.contextPath}/legacy/customers">&laquo; Back to Customer List</a></p>
    </div>

    <c:if test="${detail == null || detail.customer == null}">
    <div class="alert alert-danger">Customer not found.</div>
    </c:if>

    <c:if test="${detail != null && detail.customer != null}">
    <div style="display: flex; gap: 20px; flex-wrap: wrap;">
        <!-- Customer Info -->
        <div class="card" style="flex: 1; min-width: 350px;">
            <h3>Customer Information</h3>
            <div class="info-row">
                <span class="label">Customer ID:</span>
                <span class="value"><c:out value="${detail.customer.customerId}"/></span>
            </div>
            <div class="info-row">
                <span class="label">Name:</span>
                <span class="value"><c:out value="${detail.customer.firstName}"/> <c:out value="${detail.customer.lastName}"/></span>
            </div>
            <div class="info-row">
                <span class="label">Email:</span>
                <span class="value"><a href="mailto:<c:out value="${detail.customer.email}"/>"><c:out value="${detail.customer.email}"/></a></span>
            </div>
            <div class="info-row">
                <span class="label">Store ID:</span>
                <span class="value"><c:out value="${detail.customer.storeId}"/></span>
            </div>
            <div class="info-row">
                <span class="label">Status:</span>
                <span class="value">
                    <c:choose>
                        <c:when test="${detail.customer.activebool}">
                            <span class="badge badge-success">Active</span>
                        </c:when>
                        <c:otherwise>
                            <span class="badge badge-danger">Inactive</span>
                        </c:otherwise>
                    </c:choose>
                </span>
            </div>
            <div class="info-row">
                <span class="label">Created:</span>
                <span class="value"><c:out value="${detail.customer.createDate}"/></span>
            </div>
        </div>

        <!-- Address Info -->
        <div class="card" style="flex: 1; min-width: 300px;">
            <h3>Address</h3>
            <c:if test="${detail.address != null}">
            <div class="info-row">
                <span class="label">Address:</span>
                <span class="value"><c:out value="${detail.address.address}"/></span>
            </div>
            <div class="info-row">
                <span class="label">Address 2:</span>
                <span class="value"><c:out value="${detail.address.address2}"/></span>
            </div>
            <div class="info-row">
                <span class="label">District:</span>
                <span class="value"><c:out value="${detail.address.district}"/></span>
            </div>
            <div class="info-row">
                <span class="label">Postal Code:</span>
                <span class="value"><c:out value="${detail.address.postalCode}"/></span>
            </div>
            <div class="info-row">
                <span class="label">Phone:</span>
                <span class="value"><c:out value="${detail.address.phone}"/></span>
            </div>
            </c:if>
            <c:if test="${detail.address == null}">
            <p style="color: #95a5a6;">No address record.</p>
            </c:if>
            <c:if test="${detail.city != null}">
            <div class="info-row">
                <span class="label">City:</span>
                <span class="value"><c:out value="${detail.city.city}"/></span>
            </div>
            </c:if>
            <c:if test="${detail.country != null}">
            <div class="info-row">
                <span class="label">Country:</span>
                <span class="value"><c:out value="${detail.country.country}"/></span>
            </div>
            </c:if>
        </div>

        <!-- Balance Card -->
        <div class="card" style="flex: 0 0 200px;">
            <h3>Account Balance</h3>
            <c:if test="${balance != null}">
            <div style="text-align: center;">
                <div style="font-size: 28px; font-weight: bold; color: ${balance.balance < 0 ? '#e74c3c' : '#27ae60'};">
                    <fmt:formatNumber value="${balance.balance}" type="currency" currencySymbol="$"/>
                </div>
                <div style="font-size: 12px; color: #7f8c8d; margin-top: 5px;">
                    (from get_customer_balance procedure)
                </div>
            </div>
            </c:if>
            <c:if test="${balance == null}">
            <p style="color: #95a5a6;">Balance unavailable.</p>
            </c:if>
        </div>
    </div>

    <!-- Rental History -->
    <div class="card">
        <h3>Rental History</h3>
        <c:if test="${not empty rentals}">
        <table>
            <thead>
                <tr>
                    <th>Rental ID</th>
                    <th>Rental Date</th>
                    <th>Return Date</th>
                    <th>Inventory ID</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
                <c:forEach var="rental" items="${rentals}">
                <tr class="${rental.returnDate == null ? 'overdue' : ''}">
                    <td><c:out value="${rental.rentalId}"/></td>
                    <td><c:out value="${rental.rentalDate}"/></td>
                    <td>
                        <c:if test="${rental.returnDate != null}">
                            <c:out value="${rental.returnDate}"/>
                        </c:if>
                        <c:if test="${rental.returnDate == null}">
                            <span class="badge badge-danger">Not Returned</span>
                        </c:if>
                    </td>
                    <td><c:out value="${rental.inventoryId}"/></td>
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
            </tbody>
        </table>
        </c:if>
        <c:if test="${empty rentals}">
        <p style="color: #95a5a6;">No rental history.</p>
        </c:if>
    </div>
    </c:if>
</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Customer Detail"/>
</jsp:include>
