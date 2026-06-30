const CustomerList = {
    template: `
<div>
    <h1 class="page-title">Customer Management</h1>
    <div class="search-bar">
        <input class="search-input" v-model="keyword" @keyup.enter="doSearch" placeholder="Search customers by name or email...">
        <button class="btn btn-primary" @click="doSearch">Search</button>
    </div>

    <div class="card" v-if="!loading">
        <table class="data-table">
            <thead><tr><th>ID</th><th>Name</th><th>Email</th><th>City</th><th>Country</th><th>Status</th></tr></thead>
            <tbody>
                <tr v-for="c in customers" :key="c.customerId || c.id" class="clickable" @click="$router.push('/customers/' + (c.customerId || c.id))">
                    <td>{{ c.customerId || c.id }}</td>
                    <td>{{ c.firstName }} {{ c.lastName }}</td>
                    <td>{{ c.email || '-' }}</td>
                    <td>{{ c.city || c.cityName || '-' }}</td>
                    <td>{{ c.country || c.countryName || '-' }}</td>
                    <td><span :class="c.activebool || c.active ? 'badge badge-success' : 'badge badge-danger'">{{ (c.activebool || c.active) ? 'Active' : 'Inactive' }}</span></td>
                </tr>
            </tbody>
        </table>
    </div>

    <div class="pagination" v-if="totalPages > 1">
        <button :disabled="page <= 1" @click="goPage(page - 1)">Prev</button>
        <span>Page {{ page }} / {{ totalPages }}</span>
        <button :disabled="page >= totalPages" @click="goPage(page + 1)">Next</button>
    </div>

    <div v-if="loading" class="loading"><div class="spinner"></div></div>
</div>`,
    data() { return { customers: [], keyword: '', page: 1, size: 20, totalPages: 0, loading: false }; },
    mounted() { this.fetchCustomers(); },
    methods: {
        async fetchCustomers() {
            this.loading = true;
            try {
                const res = await fetch(`/ogagila/api/customers?page=${this.page}&size=${this.size}`);
                if (!res.ok) throw new Error('Failed');
                const data = await res.json();
                this.customers = data.list || data;
                this.totalPages = data.totalPages || 1;
            } catch (e) {}
            finally { this.loading = false; }
        },
        doSearch() { this.page = 1; this.fetchCustomers(); },
        goPage(p) { this.page = p; this.fetchCustomers(); }
    }
};
