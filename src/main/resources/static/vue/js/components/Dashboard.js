const Dashboard = {
    template: `
<div>
    <h1 class="page-title">Dashboard</h1>
    <div class="stats-grid">
        <div class="stat-card"><div class="stat-label">Total Films</div><div class="stat-value">{{ stats.filmCount || 0 }}</div></div>
        <div class="stat-card" style="border-left-color:#38a169"><div class="stat-label">Total Customers</div><div class="stat-value">{{ stats.customerCount || 0 }}</div></div>
        <div class="stat-card" style="border-left-color:#d69e2e"><div class="stat-label">Total Rentals</div><div class="stat-value">{{ stats.rentalCount || 0 }}</div></div>
        <div class="stat-card" style="border-left-color:#e53e3e"><div class="stat-label">Total Revenue</div><div class="stat-value">\${{ formatAmount(stats.totalRevenue) }}</div></div>
    </div>

    <div class="stats-grid">
        <div class="stat-card" style="border-left-color:#e53e3e"><div class="stat-label">Overdue Rentals</div><div class="stat-value">{{ stats.overdueCount || 0 }}</div></div>
        <div class="stat-card" style="border-left-color:#805ad5"><div class="stat-label">Avg Revenue/Month</div><div class="stat-value">\${{ formatAmount(stats.avgMonthlyRevenue) }}</div></div>
    </div>

    <div class="card" v-if="stats.topFilms">
        <div class="card-header">Top 5 Rented Films</div>
        <table class="data-table">
            <thead><tr><th>#</th><th>Title</th><th>Rentals</th></tr></thead>
            <tbody>
                <tr v-for="(f, i) in stats.topFilms" :key="i">
                    <td>{{ i + 1 }}</td>
                    <td>{{ f.title }}</td>
                    <td>{{ f.rentalCount }}</td>
                </tr>
            </tbody>
        </table>
    </div>

    <div class="card" v-if="stats.monthlyRevenue">
        <div class="card-header">Monthly Revenue</div>
        <div v-for="m in stats.monthlyRevenue" :key="m.month" class="chart-bar">
            <div class="chart-bar-label">{{ m.month }}</div>
            <div class="chart-bar-fill" :style="{width: barWidth(m.amount) + '%'}"></div>
            <div class="chart-bar-value">\${{ formatAmount(m.amount) }}</div>
        </div>
    </div>

    <div v-if="loading" class="loading"><div class="spinner"></div><p>Loading dashboard...</p></div>
    <div v-if="error" class="loading" style="color:#e53e3e">{{ error }}</div>
</div>`,
    data() {
        return { stats: {}, loading: true, error: null };
    },
    mounted() { this.fetchDashboard(); },
    methods: {
        async fetchDashboard() {
            try {
                const res = await fetch('/ogagila/api/reports/dashboard');
                if (!res.ok) throw new Error('Failed to load dashboard');
                this.stats = await res.json();
            } catch (e) { this.error = e.message; }
            finally { this.loading = false; }
        },
        formatAmount(v) { return v ? Number(v).toFixed(2) : '0.00'; },
        barWidth(amount) {
            const max = Math.max(...(this.stats.monthlyRevenue || []).map(m => m.amount), 1);
            return (amount / max) * 60;
        }
    }
};
