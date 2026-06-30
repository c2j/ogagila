const PaymentList = {
    template: `
<div>
    <h1 class="page-title">Payment Records</h1>
    <div class="stats-grid" v-if="monthlyRevenue !== null">
        <div class="stat-card"><div class="stat-label">Monthly Revenue</div><div class="stat-value">\${{ monthlyRevenue.toFixed(2) }}</div></div>
    </div>
    <div class="card" v-if="partitionInfo.length">
        <div class="card-header">GaussDB Partition Info (payment table)</div>
        <table class="data-table">
            <thead><tr><th>Partition</th><th>Rows</th></tr></thead>
            <tbody><tr v-for="p in partitionInfo" :key="p.name"><td>{{ p.name }}</td><td>{{ p.rows }}</td></tr></tbody>
        </table>
    </div>
    <div class="card">
        <div class="card-header">All Payments</div>
        <table class="data-table">
            <thead><tr><th>ID</th><th>Customer</th><th>Amount</th><th>Date</th></tr></thead>
            <tbody>
                <tr v-for="p in payments" :key="p.paymentId">
                    <td>{{ p.paymentId }}</td>
                    <td>{{ p.customerName || p.customerId }}</td>
                    <td style="font-weight:600;color:var(--success)">\${{ p.amount }}</td>
                    <td>{{ p.paymentDate }}</td>
                </tr>
            </tbody>
        </table>
        <div class="pagination" v-if="totalPages > 1">
            <button :disabled="page <= 1" @click="goPage(page - 1)">Prev</button>
            <span>Page {{ page }} / {{ totalPages }}</span>
            <button :disabled="page >= totalPages" @click="goPage(page + 1)">Next</button>
        </div>
    </div>
    <div v-if="loading" class="loading"><div class="spinner"></div></div>
</div>`,
    data() { return { payments: [], partitionInfo: [], monthlyRevenue: null, page: 1, size: 20, totalPages: 0, loading: false }; },
    mounted() { this.fetchPayments(); this.fetchPartitionInfo(); this.fetchMonthlyRevenue(); },
    methods: {
        async fetchPayments() {
            this.loading = true;
            try {
                const res = await fetch(`/ogagila/api/payments?page=${this.page}&size=${this.size}`);
                if (res.ok) { const d = await res.json(); this.payments = d.list || d; this.totalPages = d.totalPages || 1; }
            } catch (e) {}
            finally { this.loading = false; }
        },
        async fetchPartitionInfo() {
            try { const res = await fetch('/ogagila/api/payments/partition-info'); if (res.ok) this.partitionInfo = await res.json(); } catch (e) {}
        },
        async fetchMonthlyRevenue() {
            try { const res = await fetch('/ogagila/api/payments/monthly-revenue'); if (res.ok) this.monthlyRevenue = await res.json(); } catch (e) {}
        },
        goPage(p) { this.page = p; this.fetchPayments(); }
    }
};
