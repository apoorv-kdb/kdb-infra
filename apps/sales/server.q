/ apps/sales/server.q
/ Sales app server.
/ Start: q apps/sales/server.q -p 5010 -dbPath C:/data/databases/prod_parallel

ROOT:rtrim ssr[{$[10h=type x;x;first x]} system "cd"; "\\"; "/"]
system "l ",ROOT,"/server/server_init.q";

/ Load domain configs (registers sources, orchestrator stubs)
loadDomainConfigs[`sales];

/ ============================================================================
/ APP-SPECIFIC MODULES (explicit opt-in)
/ ============================================================================

system "l ",ROOT,"/lib/cat_handlers.q";
system "l ",ROOT,"/lib/query.q";

/ ============================================================================
/ CATALOG
/ ============================================================================

opts:.Q.opt .z.x;
.srv.catPath:$[`catPath in key opts; first opts`catPath; ROOT,"/config/catalog_sales.csv"];
.catalog.load[.srv.catPath; `sales];

/ ============================================================================
/ CACHE
/ ============================================================================

.cache.register[`sales_by_region; `sales_by_region; 9999; ::];
.cache.loadAll[];
.cache.startRefresh[600000];

/ ============================================================================
/ HTTP ROUTES
/ ============================================================================

.http.addRoute[`GET;  "/catalog/fields";        .catHandler.fields];
.http.addRoute[`GET;  "/catalog/filter-options"; .catHandler.filterOptions];
.http.addRoute[`POST; "/query/table";            .qryHandler.table];
.http.addRoute[`POST; "/query/spot";             .qryHandler.spot];
.http.addRoute[`POST; "/query/trend";            .qryHandler.trend];

/ ============================================================================
/ STARTUP SUMMARY
/ ============================================================================

show "";
show "========================================";
show "Sales server ready";
show "  DB:      ",string .dbWriter.dbPath;
show "  Catalog: ",.srv.catPath;
show "  Routes:";
show "    GET  /catalog/fields";
show "    GET  /catalog/filter-options";
show "    POST /query/table";
show "    POST /query/spot";
show "    POST /query/trend";
show "========================================";
show "";
