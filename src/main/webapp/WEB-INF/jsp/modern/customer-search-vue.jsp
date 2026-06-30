<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<%@ taglib prefix="c" uri="jakarta.tags.core" %>
<%@ taglib prefix="fmt" uri="jakarta.tags.fmt" %>
<%
    request.setAttribute("param.pageTitle", "Vue Customer Search");
%>
<%@ include file="/WEB-INF/jsp/common/header.jspf" %>

<!-- Vue 3 from CDN -->
<script src="https://unpkg.com/vue@3/dist/vue.global.prod.js"></script>

<div class="container">

    <div class="page-header">
        <h2>Customer Search <span style="font-size:14px; color:#27ae60;">(Vue 3 Progressive)</span></h2>
        <p>Transitional architecture - Vue-powered search with real-time filtering</p>
    </div>

    <div class="alert alert-info">
        <strong>Hybrid Pattern:</strong> This page demonstrates how legacy JSP applications can incrementally
        adopt Vue.js. The initial customer data is rendered as a JSON blob by the JSP. Vue takes over
        all client-side interactivity including real-time search filtering and reactive table updates.
    </div>

    <!-- Vue 3 App Mount Point -->
    <div id="customer-app">
        <div class="search-form" style="display:flex; gap:10px; align-items:center; flex-wrap:wrap;">
            <input type="text" v-model="searchQuery" placeholder="Type to search customers by name, email..."
                   style="padding:7px 12px; border:1px solid #bdc3c7; border-radius:3px; flex:1; min-width:250px; font-size:14px;"
                   v-on:input="onSearchInput"/>
            <select v-model="statusFilter"
                    style="padding:7px 12px; border:1px solid #bdc3c7; border-radius:3px; font-size:13px; background:#fff;">
                <option value="all">All Status</option>
                <option value="active">Active Only</option>
                <option value="inactive">Inactive Only</option>
            </select>
            <span style="font-size:13px; color:#7f8c8d;">
                {{ filteredCustomers.length }} results
            </span>
        </div>

        <table>
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Name</th>
                    <th>Email</th>
                    <th>Status</th>
                    <th>Created</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
                <tr v-for="customer in filteredCustomers" :key="customer.customerId">
                    <td>{{ customer.customerId }}</td>
                    <td>{{ customer.firstName }} {{ customer.lastName }}</td>
                    <td><a :href="'mailto:' + customer.email">{{ customer.email }}</a></td>
                    <td>
                        <span v-if="customer.activebool" class="badge badge-success">Active</span>
                        <span v-else class="badge badge-danger">Inactive</span>
                    </td>
                    <td>{{ formatDate(customer.createDate) }}</td>
                    <td>
                        <a :href="contextPath + '/legacy/customers/' + customer.customerId" class="btn btn-primary btn-sm">Detail</a>
                    </td>
                </tr>
            </tbody>
        </table>

        <div v-if="filteredCustomers.length === 0"
             style="text-align:center; padding:40px; color:#95a5a6;">
            No customers match your search.
        </div>
    </div>

    <!-- Vue 3 App Initialization -->
    <script>
        window.initialCustomerData = ${customerListJson};
        window.contextPath = '${pageContext.request.contextPath}';

        const { createApp, ref, computed } = Vue;

        const customerApp = createApp({
            setup() {
                const customers = ref(window.initialCustomerData || []);
                const searchQuery = ref('');
                const statusFilter = ref('all');

                const filteredCustomers = computed(function() {
                    let result = customers.value;
                    const query = searchQuery.value.toLowerCase().trim();

                    // Apply text search
                    if (query) {
                        result = result.filter(function(c) {
                            const fullName = (c.firstName + ' ' + c.lastName).toLowerCase();
                            const email = (c.email || '').toLowerCase();
                            return fullName.indexOf(query) !== -1
                                || email.indexOf(query) !== -1;
                        });
                    }

                    // Apply status filter
                    if (statusFilter.value === 'active') {
                        result = result.filter(function(c) { return c.activebool === true; });
                    } else if (statusFilter.value === 'inactive') {
                        result = result.filter(function(c) { return c.activebool === false; });
                    }

                    return result;
                });

                function formatDate(dateStr) {
                    if (!dateStr) return '';
                    return dateStr.substring(0, 10);
                }

                return {
                    customers: customers.value,
                    searchQuery,
                    statusFilter,
                    filteredCustomers,
                    contextPath: window.contextPath,
                    formatDate
                };
            }
        });

        customerApp.mount('#customer-app');
    </script>

</div>

<jsp:include page="/WEB-INF/jsp/common/footer.jspf">
    <jsp:param name="pageName" value="Vue Customer Search"/>
</jsp:include>
