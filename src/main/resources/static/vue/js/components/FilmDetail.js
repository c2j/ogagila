const FilmDetail = {
    props: ['id'],
    template: `
<div>
    <button class="btn btn-sm" style="margin-bottom:16px" @click="$router.push('/films')">← Back to Films</button>
    <div v-if="film" class="card">
        <h1 class="page-title" style="margin-bottom:8px">{{ film.title }}</h1>
        <div class="detail-grid">
            <div>
                <p style="color:var(--text-muted);margin-bottom:12px">{{ film.description }}</p>
                <p><strong>Release Year:</strong> {{ film.releaseYear }}</p>
                <p><strong>Rating:</strong> <span class="badge" :class="ratingBadge(film.rating)">{{ film.rating }}</span></p>
                <p><strong>Length:</strong> {{ film.length || 'N/A' }} minutes</p>
                <p><strong>Rental Rate:</strong> \${{ film.rentalRate }}</p>
                <p><strong>Rental Duration:</strong> {{ film.rentalDuration }} days</p>
                <p><strong>Replacement Cost:</strong> \${{ film.replacementCost }}</p>
            </div>
            <div>
                <div v-if="actors.length" style="margin-bottom:16px">
                    <strong>Actors:</strong>
                    <p v-for="a in actors" :key="a.actorId" style="margin:2px 0">{{ a.firstName }} {{ a.lastName }}</p>
                </div>
                <div v-if="categories.length">
                    <strong>Categories:</strong>
                    <p v-for="c in categories" :key="c.categoryId" style="margin:2px 0">{{ c.name }}</p>
                </div>
            </div>
        </div>
        <div v-if="stockInfo !== null" style="margin-top:16px;padding-top:16px;border-top:1px solid var(--border)">
            <strong>Stock Availability:</strong>
            <span :class="stockInfo.inStock ? 'badge badge-success' : 'badge badge-danger'">
                {{ stockInfo.inStock ? 'IN STOCK' : 'OUT OF STOCK' }}
            </span>
        </div>
    </div>
    <div v-if="loading" class="loading"><div class="spinner"></div></div>
    <div v-if="error" class="loading" style="color:#e53e3e">{{ error }}</div>
</div>`,
    data() { return { film: null, actors: [], categories: [], stockInfo: null, loading: true, error: null }; },
    mounted() { this.fetchDetail(); },
    methods: {
        async fetchDetail() {
            try {
                const [filmRes, stockRes] = await Promise.all([
                    fetch(`/ogagila/api/films/detail/${this.id}`),
                    fetch(`/ogagila/api/procedures/film-in-stock/${this.id}/1`)
                ]);
                if (filmRes.ok) {
                    const d = await filmRes.json();
                    this.film = d.film || d;
                    this.actors = d.actors || [];
                    this.categories = d.categories || [];
                } else { throw new Error('Film not found'); }
                if (stockRes.ok) { this.stockInfo = { inStock: (await stockRes.json()).length > 0 }; }
            } catch (e) { this.error = e.message; }
            finally { this.loading = false; }
        },
        ratingBadge(r) {
            const map = { 'G': 'badge-success', 'PG': 'badge-info', 'PG-13': 'badge-warning', 'R': 'badge-danger' };
            return map[r] || 'badge-info';
        }
    }
};
