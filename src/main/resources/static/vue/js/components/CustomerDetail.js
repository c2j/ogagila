const CustomerDetail = {
    props: ['id'],
    template: `
<div>
    <button class="btn btn-sm" style="margin-bottom:16px" @click="$router.push('/customers')">← Back to Customers</button>
    <div v-if="detail" class="detail-grid">
        <div class="card">
            <div class="card-header">Customer Info</div>
            <p><strong>Name:</strong> {{ detail.customer.firstName }} {{ detail.customer.lastName }}</p>
            <p><strong>Email:</strong> {{ detail.customer.email || '-' }}</p>
            <p><strong>Status:</strong> <span :class="detail.customer.activebool ? 'badge badge-success' : 'badge badge-danger'">{{ detail.customer.activebool ? 'Active' : 'Inactive' }}</span></p>
            <p><strong>Member Since:</strong> {{ detail.customer.createDate }}</p>
        </div>
        <div class="card">
            <div class="card-header">Address</div>
            <p v-if="detail.address">{{ detail.address.address }}</p>
            <p v-if="detail.address && detail.address.district">{{ detail.address.district }}</p>
            <p v-if="detail.city">{{ detail.city.city }}, {{ detail.country ? detail.country.country : '' }}</p>
            <p v-if="detail.address && detail.address.phone">📞 {{ detail.address.phone }}</p>
        </div>
        <div class="card full-width" v-if="balance !== null">
            <div class="card-header">Account Balance</div>
            <p style="font-size:1.5em;font-weight:700" :style="{color: balance >= 0 ? '#38a169' : '#e53e3e'}">\${{ balance.toFixed(2) }}</p>
        </div>
        <div class="card full-width" v-if="rentals.length">
            <div class="card-header">Recent Rentals</div>
            <table class="data-table">
                <thead><tr><th>Date</th><th>Film</th><th>Returned</th></tr></thead>
                <tbody>
                    <tr v-for="r in rentals" :key="r.rentalId">
                        <td>{{ r.rentalDate }}</td>
                        <td>{{ r.filmTitle || '-' }}</td>
                        <td><span :class="r.returnDate ? 'badge badge-success' : 'badge badge-danger'">{{ r.returnDate || 'NOT RETURNED' }}</span></td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
    <div v-if="loading" class="loading"><div class="spinner"></div></div>
    <div v-if="error" class="loading" style="color:#e53e3e">{{ error }}</div>
</div>`,
    data() { return { detail: null, rentals: [], balance: null, loading: true, error: null }; },
    mounted() { this.fetchData(); },
    methods: {
        async fetchData() {
            try {
                const [detRes, balRes, renRes] = await Promise.all([
                    fetch(`/ogagila/api/customers/detail/${this.id}`),
                    fetch(`/ogagila/api/procedures/customer-balance/${this.id}`),
                    fetch(`/ogagila/api/rentals/by-customer/${this.id}`)
                ]);
                if (detRes.ok) this.detail = await detRes.json();
                if (balRes.ok) this.balance = await balRes.json();
                if (renRes.ok) {
                    const rData = await renRes.json();
                    this.rentals = (rData.list || rData || []).slice(0, 10);
                }
            } catch (e) { this.error = e.message; }
            finally { this.loading = false; }
        }
    }
};
