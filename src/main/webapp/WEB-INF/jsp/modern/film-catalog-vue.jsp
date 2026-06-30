<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Vue Film Catalog");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<!-- Vue 3 from CDN -->
<script src="https://unpkg.com/vue@3/dist/vue.global.prod.js"></script>

<div class="container">

    <div class="page-header">
        <h2>Film Catalog <span style="font-size:14px; color:#27ae60;">(Vue 3 Progressive)</span></h2>
        <p>Transitional architecture - JSP shell with Vue 3 CDN components for reactive interactivity</p>
    </div>

    <div class="alert alert-info">
        <strong>Transitional Pattern:</strong> This JSP page embeds Vue 3 via CDN. The server provides initial data
        as JSON, and Vue handles filtering and rendering on the client side. This demonstrates progressive
        modernization of a legacy JSP application.
    </div>

    <!-- Vue 3 App Mount Point -->
    <div id="app">
        <div class="search-form">
            <input type="text" v-model="searchQuery" placeholder="Type to filter films by title..."
                   style="padding:7px 12px; border:1px solid #bdc3c7; border-radius:3px; width:100%; font-size:14px;"
                   v-on:input="onSearchInput"/>
        </div>

        <div style="margin-bottom:10px; font-size:13px; color:#7f8c8d;">
            Showing <strong>{{ filteredFilms.length }}</strong> of <strong>{{ films.length }}</strong> films
        </div>

        <div style="display: flex; flex-wrap: wrap; gap: 15px;">
            <div v-for="film in filteredFilms" :key="film.filmId"
                 style="background:#fff; border-radius:3px; box-shadow:0 1px 3px rgba(0,0,0,0.1); padding:15px; width:280px; border-top:3px solid #3498db;">
                <h4 style="margin:0 0 8px 0; color:#2c3e50; font-size:15px;">
                    {{ film.title }}
                </h4>
                <div style="font-size:12px; color:#7f8c8d; margin-bottom:10px;">
                    {{ film.description ? film.description.substring(0, 100) + '...' : '' }}
                </div>
                <div style="display:flex; justify-content:space-between; font-size:13px; margin-bottom:5px;">
                    <span><strong>Rating:</strong> {{ film.rating }}</span>
                    <span><strong>Length:</strong> {{ film.length }} min</span>
                </div>
                <div style="display:flex; justify-content:space-between; font-size:13px;">
                    <span><strong>Rate:</strong> \${{ film.rentalRate ? film.rentalRate.toFixed(2) : '0.00' }}</span>
                    <span><strong>Duration:</strong> {{ film.rentalDuration }} days</span>
                </div>
                <div style="margin-top:10px; text-align:right;">
                    <a :href="contextPath + '/legacy/films/' + film.filmId" class="btn btn-primary btn-sm">View Detail</a>
                </div>
            </div>
        </div>

        <div v-if="filteredFilms.length === 0"
             style="text-align:center; padding:40px; color:#95a5a6;">
            No films match your search.
        </div>
    </div>

    <!-- Vue 3 App Initialization -->
    <script>
        // Initial data from server - injected by JSP
        window.initialData = ${filmListJson};
        window.contextPath = '${pageContext.request.contextPath}';

        const { createApp, ref, computed } = Vue;

        const app = createApp({
            setup() {
                const films = ref(window.initialData || []);
                const searchQuery = ref('');

                const filteredFilms = computed(() => {
                    const query = searchQuery.value.toLowerCase().trim();
                    if (!query) {
                        return films.value;
                    }
                    return films.value.filter(function(film) {
                        return (film.title && film.title.toLowerCase().indexOf(query) !== -1)
                            || (film.description && film.description.toLowerCase().indexOf(query) !== -1);
                    });
                });

                return {
                    films: films.value,
                    searchQuery,
                    filteredFilms,
                    contextPath: window.contextPath
                };
            }
        });

        app.mount('#app');
    </script>

</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Vue Film Catalog"/>
</jsp:include>
