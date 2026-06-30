const FilmCatalog = {
    template: `
<div>
    <h1 class="page-title">Film Catalog</h1>
    <div class="search-bar">
        <input class="search-input" v-model="keyword" @keyup.enter="search" placeholder="Fulltext search (GaussDB tsvector)...">
        <button class="btn btn-primary" @click="search">Search</button>
        <select class="search-input" style="max-width:200px" v-model="categoryFilter" @change="fetchFilms">
            <option value="">All Categories</option>
            <option v-for="c in categories" :key="c.categoryId" :value="c.categoryId">{{ c.name }}</option>
        </select>
    </div>

    <div class="film-grid" v-if="!loading && films.length > 0">
        <div v-for="film in films" :key="film.filmId" class="film-card" @click="$router.push('/films/' + film.filmId)">
            <h3>{{ film.title }}</h3>
            <p style="font-size:0.85em;color:var(--text-muted);margin-bottom:8px">{{ truncate(film.description, 100) }}</p>
            <div class="film-meta">
                <span class="badge" :class="ratingBadge(film.rating)">{{ film.rating }}</span>
                <span>{{ film.length || '?' }} min</span>
                <span style="color:var(--accent);font-weight:600">\${{ film.rentalRate }}</span>
            </div>
        </div>
    </div>

    <div class="pagination" v-if="totalPages > 1">
        <button :disabled="page <= 1" @click="goPage(page - 1)">Prev</button>
        <span>Page {{ page }} / {{ totalPages }} ({{ total }} films)</span>
        <button :disabled="page >= totalPages" @click="goPage(page + 1)">Next</button>
    </div>

    <div v-if="loading" class="loading"><div class="spinner"></div></div>
    <div v-if="!loading && films.length === 0" class="loading">No films found.</div>
    <div v-if="error" class="loading" style="color:#e53e3e">{{ error }}</div>
</div>`,
    data() {
        return { films: [], categories: [], keyword: '', categoryFilter: '', page: 1, size: 12, total: 0, totalPages: 0, loading: false, error: null };
    },
    mounted() { this.fetchCategories(); this.fetchFilms(); },
    methods: {
        async fetchFilms() {
            this.loading = true; this.error = null;
            try {
                let url = this.keyword
                    ? `/ogagila/api/films/search?keyword=${encodeURIComponent(this.keyword)}&page=${this.page}&size=${this.size}`
                    : `/ogagila/api/films?page=${this.page}&size=${this.size}`;
                const res = await fetch(url);
                if (!res.ok) throw new Error('Failed to load films');
                const data = await res.json();
                this.films = data.list || data;
                this.total = data.total || 0;
                this.totalPages = data.totalPages || 1;
            } catch (e) { this.error = e.message; }
            finally { this.loading = false; }
        },
        async fetchCategories() {
            try {
                const res = await fetch('/ogagila/api/films');
                this.categories = [];
            } catch (e) {}
        },
        search() { this.page = 1; this.fetchFilms(); },
        goPage(p) { this.page = p; this.fetchFilms(); },
        truncate(s, n) { return s && s.length > n ? s.substring(0, n) + '...' : s; },
        ratingBadge(r) {
            const map = { 'G': 'badge-success', 'PG': 'badge-info', 'PG-13': 'badge-warning', 'R': 'badge-danger', 'NC-17': 'badge-danger' };
            return map[r] || 'badge-info';
        }
    }
};
