const { createRouter, createWebHashHistory } = VueRouter;

const routes = [
    { path: '/', component: Dashboard },
    { path: '/films', component: FilmCatalog },
    { path: '/films/:id', component: FilmDetail, props: true },
    { path: '/customers', component: CustomerList },
    { path: '/customers/:id', component: CustomerDetail, props: true },
    { path: '/rentals', component: RentalList },
    { path: '/payments', component: PaymentList },
    { path: '/reports', component: Reports },
    { path: '/jsonb', component: JsonbExplorer }
];

const router = createRouter({ history: createWebHashHistory(), routes });

const app = Vue.createApp({
    template: '<router-view></router-view>'
});
app.use(router);
app.mount('#app');
