<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Film Detail");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<div class="container">

    <div class="page-header">
        <h2>Film Detail</h2>
        <p><a href="${pageContext.request.contextPath}/legacy/films">&laquo; Back to Film List</a></p>
    </div>

    <c:if test="${detail == null || detail.film == null}">
    <div class="alert alert-danger">Film not found.</div>
    </c:if>

    <c:if test="${detail != null && detail.film != null}">
    <div style="display: flex; gap: 20px; flex-wrap: wrap;">
        <!-- Film Info Card -->
        <div class="card" style="flex: 2; min-width: 400px;">
            <h3><c:out value="${detail.film.title}"/></h3>

            <div class="info-row">
                <span class="label">Film ID:</span>
                <span class="value"><c:out value="${detail.film.filmId}"/></span>
            </div>
            <div class="info-row">
                <span class="label">Description:</span>
                <span class="value"><c:out value="${detail.film.description}"/></span>
            </div>
            <div class="info-row">
                <span class="label">Release Year:</span>
                <span class="value"><c:out value="${detail.film.releaseYear}"/></span>
            </div>
            <div class="info-row">
                <span class="label">Rating:</span>
                <span class="value"><span class="badge badge-info"><c:out value="${detail.film.rating}"/></span></span>
            </div>
            <div class="info-row">
                <span class="label">Length:</span>
                <span class="value"><c:out value="${detail.film.length}"/> minutes</span>
            </div>
            <div class="info-row">
                <span class="label">Rental Rate:</span>
                <span class="value"><fmt:formatNumber value="${detail.film.rentalRate}" type="currency" currencySymbol="$"/></span>
            </div>
            <div class="info-row">
                <span class="label">Rental Duration:</span>
                <span class="value"><c:out value="${detail.film.rentalDuration}"/> days</span>
            </div>
            <div class="info-row">
                <span class="label">Replacement Cost:</span>
                <span class="value"><fmt:formatNumber value="${detail.film.replacementCost}" type="currency" currencySymbol="$"/></span>
            </div>
            <div class="info-row">
                <span class="label">Special Features:</span>
                <span class="value">
                    <c:if test="${detail.film.specialFeatures != null}">
                        <c:forEach var="feature" items="${detail.film.specialFeatures}">
                            <span class="badge badge-success"><c:out value="${feature}"/></span>
                        </c:forEach>
                    </c:if>
                    <c:if test="${detail.film.specialFeatures == null}">
                        <em>None</em>
                    </c:if>
                </span>
            </div>
        </div>

        <!-- Actors Card -->
        <div class="card" style="flex: 1; min-width: 250px;">
            <h3>Cast (Actors)</h3>
            <c:if test="${not empty detail.actors}">
            <ul style="list-style: none;">
                <c:forEach var="actor" items="${detail.actors}">
                <li style="padding: 5px 0; border-bottom: 1px solid #ecf0f1;">
                    <c:out value="${actor.firstName}"/> <c:out value="${actor.lastName}"/>
                </li>
                </c:forEach>
            </ul>
            </c:if>
            <c:if test="${empty detail.actors}">
            <p style="color: #95a5a6;">No actors listed.</p>
            </c:if>
        </div>

        <!-- Categories Card -->
        <div class="card" style="flex: 1; min-width: 200px;">
            <h3>Categories</h3>
            <c:if test="${not empty detail.categories}">
            <ul style="list-style: none;">
                <c:forEach var="category" items="${detail.categories}">
                <li style="padding: 5px 0; border-bottom: 1px solid #ecf0f1;">
                    <span class="badge badge-info"><c:out value="${category.name}"/></span>
                </li>
                </c:forEach>
            </ul>
            </c:if>
            <c:if test="${empty detail.categories}">
            <p style="color: #95a5a6;">No categories assigned.</p>
            </c:if>
        </div>
    </div>

    <!-- Overdue Stats -->
    <div class="card">
        <h3>Overdue Rental Statistics</h3>
        <c:if test="${not empty overdue}">
        <table>
            <tr>
                <th>Film ID</th>
                <th>Title</th>
                <th>Overdue Count</th>
                <th>Rental Duration</th>
                <th>Trailer Info</th>
                <th>Rank</th>
            </tr>
            <c:forEach var="od" items="${overdue}">
            <tr>
                <td><c:out value="${od.film_id}"/></td>
                <td><c:out value="${od.title}"/></td>
                <td><c:out value="${od.overdue_count}"/></td>
                <td><c:out value="${od.rental_duration}"/> days</td>
                <td><c:out value="${od.trailer_info}"/></td>
                <td><c:out value="${od.overdue_rank}"/></td>
            </tr>
            </c:forEach>
        </table>
        </c:if>
        <c:if test="${empty overdue}">
        <p style="color: #95a5a6;">No overdue statistics available.</p>
        </c:if>
    </div>

    <div style="margin-top: 20px;">
        <a href="${pageContext.request.contextPath}/legacy/rentals" class="btn btn-success">Rent This Film</a>
        <a href="${pageContext.request.contextPath}/legacy/films" class="btn btn-default">&laquo; Back to Films</a>
    </div>
    </c:if>
</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Film Detail"/>
</jsp:include>
