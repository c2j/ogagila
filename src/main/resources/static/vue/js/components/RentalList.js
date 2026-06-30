const RentalList = {
    template: `
<div>
    <h1 class="page-title">Rental Management</h1>
    <div class="card">
        <div class="card-header">Overdue Rentals <span class="badge badge-danger" style="margin-left:8px">{{ overdues.length }} overdue</span></div>
        <table class="data-table" v-if="overdues.length">
            <thead><tr><th>Rental ID</th><th>Customer</th><th>Rental Date</th><th>Days Overdue</th><th>Action</th></tr></thead>
            <tbody>
                <tr v-for="r in overdues" :key="r.rentalId" style="background:#fff5f5">
                    <td>{{ r.rentalId }}</td>
                    <td>{{ r.customerName || '-' }}</td>
                    <td>{{ r.rentalDate }}</td>
                    <td><span class="badge badge-danger">{{ daysSince(r.rentalDate) }}d</span></td>
                    <td><button class="btn btn-sm btn-success" @click="returnRental(r.rentalId)">Return</button></td>
                </tr>
            </tbody>
        </table>
        <p v-else style="color:var(--success);padding:12px">No overdue rentals!</p>
    </div>

    <div class="card">
        <div class="card-header">Recent Rentals</div>
        <table class="data-table">
            <thead><tr><th>ID</th><th>Customer</th><th>Staff</th><th>Rental Date</th><th>Return Date</th><th>Status</th></tr></thead>
            <tbody>
                <tr v-for="r in rentals" :key="r.rentalId">
                    <td>{{ r.rentalId }}</td>
                    <td>{{ r.customerName || '-' }}</td>
                    <td>{{ r.staffId }}</td>
                    <td>{{ r.rentalDate }}</td>
                    <td>{{ r.returnDate || '-' }}</td>
                    <td><span :class="r.returnDate ? 'badge badge-success' : 'badge badge-danger'">{{ r.returnDate ? 'Returned' : 'Active' }}</span></td>
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
    data() { return { rentals: [], overdues: [], page: 1, size: 20, totalPages: 0, loading: false }; },
    mounted() { this.fetchRentals(); this.fetchOverdues(); },
    methods: {
        async fetchRentals() {
            this.loading = true;
            try {
                const res = await fetch(`/ogagila/api/rentals?page=${this.page}&size=${this.size}`);
                if (res.ok) { const d = await res.json(); this.rentals = d.list || d; this.totalPages = d.totalPages || 1; }
            } catch (e) {}
            finally { this.loading = false; }
        },
        async fetchOverdues() {
            try {
                const res = await fetch('/ogagila/api/rentals/overdue');
                if (res.ok) { const d = await res.json(); this.overdues = d.list || d || []; }
            } catch (e) {}
        },
        async returnRental(id) {
            try {
                await fetch(`/ogagila/api/rentals/${id}/return`, { method: 'PUT' });
                this.fetchRentals(); this.fetchOverdues();
            } catch (e) {}
        },
        daysSince(dateStr) { if (!dateStr) return '?'; const d = new Date(dateStr); return Math.floor((Date.now() - d) / 86400000); },
        goPage(p) { this.page = p; this.fetchRentals(); }
    }
};
