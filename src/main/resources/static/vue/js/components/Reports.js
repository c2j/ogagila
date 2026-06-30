const Reports = {
    template: `
<div>
    <h1 class="page-title">Analytics Reports</h1>
    <div class="stats-grid">
        <div class="stat-card"><div class="stat-label">Total Films</div><div class="stat-value">{{ dashboard.filmCount || 0 }}</div></div>
        <div class="stat-card"><div class="stat-label">Total Revenue</div><div class="stat-value">\${{ formatAmount(dashboard.totalRevenue) }}</div></div>
    </div>

    <div class="card" v-if="salesByCategory.length">
        <div class="card-header">Sales by Category</div>
        <table class="data-table">
            <thead><tr><th>Category</th><th>Total Sales</th></tr></thead>
            <tbody>
                <tr v-for="s in salesByCategory" :key="s.category">
                    <td>{{ s.category }}</td>
                    <td style="font-weight:600;color:var(--success)">\${{ formatAmount(s.totalSales) }}</td>
                </tr>
            </tbody>
        </table>
    </div>

    <div class="card" v-if="salesByStore.length">
        <div class="card-header">Sales by Store</div>
        <table class="data-table">
            <thead><tr><th>Store</th><th>Manager</th><th>Total Sales</th></tr></thead>
            <tbody>
                <tr v-for="s in salesByStore" :key="s.store">
                    <td>{{ s.store }}</td>
                    <td>{{ s.manager }}</td>
                    <td style="font-weight:600">\${{ formatAmount(s.totalSales) }}</td>
                </tr>
            </tbody>
        </table>
    </div>

    <div class="card" v-if="topFilms.length">
        <div class="card-header">Top 10 Films (RANK window function)</div>
        <table class="data-table">
            <thead><tr><th>Rank</th><th>Title</th><th>Rentals</th></tr></thead>
            <tbody>
                <tr v-for="f in topFilms" :key="f.filmId">
                    <td>#{{ f.rank }}</td>
                    <td>{{ f.title }}</td>
                    <td>{{ f.rentalCount }}</td>
                </tr>
            </tbody>
        </table>
    </div>

    <div v-if="loading" class="loading"><div class="spinner"></div></div>
</div>`,
    data() { return { dashboard: {}, salesByCategory: [], salesByStore: [], topFilms: [], loading: false }; },
    mounted() { this.fetchAll(); },
    methods: {
        async fetchAll() {
            this.loading = true;
            try {
                const [dash, cat, store, films] = await Promise.all([
                    fetch('/ogagila/api/reports/dashboard'),
                    fetch('/ogagila/api/reports/sales-by-category'),
                    fetch('/ogagila/api/reports/sales-by-store'),
                    fetch('/ogagila/api/reports/top-films')
                ]);
                if (dash.ok) this.dashboard = await dash.json();
                if (cat.ok) this.salesByCategory = await cat.json();
                if (store.ok) this.salesByStore = await store.json();
                if (films.ok) this.topFilms = await films.json();
            } catch (e) {}
            finally { this.loading = false; }
        },
        formatAmount(v) { return v ? Number(v).toFixed(2) : '0.00'; }
    }
};
