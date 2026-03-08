/ apps/sales/server.q
/ Sales app server.
/ Start: q apps/sales/server.q -p 5010 -dbPath C:/data/databases/prod_parallel

ROOT:rtrim ssr[{$[10h=type x;x;first x]} system "cd"; "\\"; "/"]
system "l ",ROOT,"/server/server_init.q";

/ ============================================================================
/ APP-SPECIFIC MODULES
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
/ HTTP ROUTES — all prefixed /api/sales/
/ ============================================================================

/ Init — unified startup response (latestAsofDate, catalogFields, filterOptions, presets)
.http.addRoute[`GET;  "/api/sales/init";          .catHandler.init];

/ Catalog (also available standalone for debugging)
.http.addRoute[`GET;  "/api/sales/catalog/fields";         .catHandler.fields];
.http.addRoute[`GET;  "/api/sales/catalog/filter-options"; .catHandler.filterOptions];

/ Query handlers
.http.addRoute[`POST; "/api/sales/query/table"; .qryHandler.table];
.http.addRoute[`POST; "/api/sales/query/spot";  .qryHandler.spot];
.http.addRoute[`POST; "/api/sales/query/trend"; .qryHandler.trend];

/ ============================================================================
/ STARTUP SUMMARY
/ ============================================================================

show "";
show "========================================";
show "Sales server ready";
show "  DB:      ",string .dbWriter.dbPath;
show "  Catalog: ",.srv.catPath;
show "  Routes:";
show "    GET  /api/sales/init";
show "    GET  /api/sales/catalog/fields";
show "    GET  /api/sales/catalog/filter-options";
show "    POST /api/sales/query/table";
show "    POST /api/sales/query/spot";
show "    POST /api/sales/query/trend";
show "========================================";
show "";
