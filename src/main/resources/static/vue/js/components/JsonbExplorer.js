const JsonbExplorer = {
    template: `
<div>
    <h1 class="page-title">JSONB Explorer</h1>
    <p style="color:var(--text-muted);margin-bottom:20px">Browse openGauss JSONB extension tables containing package metadata.</p>
    <div class="search-bar">
        <input class="search-input" v-model="keyword" @keyup.enter="search" placeholder="Search packages...">
        <button class="btn btn-primary" @click="search">Search</button>
    </div>

    <div class="card" v-if="aptPackages.length">
        <div class="card-header">APT Packages (packages_apt_postgresql_org)</div>
        <table class="data-table">
            <thead><tr><th>Package</th><th>Version</th><th>JSON Data</th></tr></thead>
            <tbody>
                <tr v-for="p in aptPackages" :key="p.id || p.package">
                    <td>{{ p.package || p.name }}</td>
                    <td>{{ p.version || '-' }}</td>
                    <td><code style="font-size:0.8em;word-break:break-all">{{ JSON.stringify(p.data || p).substring(0, 100) }}...</code></td>
                </tr>
            </tbody>
        </table>
    </div>

    <div class="card" v-if="yumPackages.length">
        <div class="card-header">YUM Packages (packages_yum)</div>
        <table class="data-table">
            <thead><tr><th>Package</th><th>Version</th></tr></thead>
            <tbody>
                <tr v-for="p in yumPackages" :key="p.id || p.package">
                    <td>{{ p.package || p.name }}</td>
                    <td>{{ p.version || '-' }}</td>
                </tr>
            </tbody>
        </table>
    </div>

    <div v-if="loading" class="loading"><div class="spinner"></div></div>
    <div v-if="!loading && !aptPackages.length && !yumPackages.length" class="loading">No JSONB data found in database.</div>
</div>`,
    data() { return { aptPackages: [], yumPackages: [], keyword: '', loading: false }; },
    mounted() { this.fetchData(); },
    methods: {
        async fetchData() {
            this.loading = true;
            try {
                const [aptRes, yumRes] = await Promise.all([
                    fetch('/ogagila/api/jsonb/packages-apt'),
                    fetch('/ogagila/api/jsonb/packages-yum')
                ]);
                if (aptRes.ok) { const d = await aptRes.json(); this.aptPackages = (d.list || d || []).slice(0, 20); }
                if (yumRes.ok) { const d = await yumRes.json(); this.yumPackages = (d.list || d || []).slice(0, 20); }
            } catch (e) {}
            finally { this.loading = false; }
        },
        search() {
            if (this.keyword) {
                fetch(`/ogagila/api/jsonb/search?keyword=${encodeURIComponent(this.keyword)}`)
                    .then(r => r.json())
                    .then(d => { this.aptPackages = (d.list || d || []).slice(0, 20); })
                    .catch(() => {});
            } else { this.fetchData(); }
        }
    }
};
