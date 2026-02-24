/ apps/sales/server.q
/ Sales app server — serves data from the sales/core app and the React frontend

/ Endpoints:
/   GET  /catalog/fields          → [{field, label, type, format}]
/   GET  /catalog/filter-options  → [{key, value}]  (all categorical field values)
/   POST /query/table             → [{<field>, asofValue, prevValue, change, changePct}]
/   POST /query/trend             → [{date, category, value}]

/ Start:
/   q apps/sales/server.q -p 5010 -dbPath /data/databases/prod
/   or: ./bin/start-sales-server.sh

/ Command line args:
/   -p        port (required)
/   -dbPath   path to HDB (default: <ROOT>/curated_db)
/   -catPath  path to catalog CSV (default: <ROOT>/config/catalog_sales.csv)

/ ROOT must be set before server_init so all subsequent \l calls use absolute paths
ROOT:rtrim ssr[{$[10h=type x;x;first x]} system "cd"; "\\"; "/"]
system "l ",ROOT,"/server/server_init.q";

/ Load app schemas + register with orchestrator stubs
loadDomainConfigs[`sales];

/ ============================================================================
/ CATALOG
/ ============================================================================

opts:.Q.opt .z.x;
.srv.catPath:$[`catPath in key opts; first opts`catPath; ROOT,"/config/catalog_sales.csv"];
.catalog.load[.srv.catPath; `sales];

/ ============================================================================
/ CACHE RECIPES
/ ============================================================================

/ Regional aggregation — 1 year window for both table (DoD) and trend queries
.cache.register[`sales_by_region; `sales_by_region; 9999; ::];

.cache.loadAll[];
.cache.startRefresh[600000];  / reload from HDB every 10 minutes

/ ============================================================================
/ HTTP ROUTES
/ ============================================================================

.http.addRoute[`GET;  "/catalog/fields";        .catHandler.fields];
.http.addRoute[`GET;  "/catalog/filter-options"; .catHandler.filterOptions];
.http.addRoute[`POST; "/query/table";            .qryHandler.table];
.http.addRoute[`POST; "/query/trend";            .qryHandler.trend];

/ ============================================================================
/ STARTUP SUMMARY
/ ============================================================================

show "";
show "========================================";
show "Sales server ready";
show "========================================";
show "DB:      ",string .dbWriter.dbPath;
show "Catalog: ",.srv.catPath;
show "Routes:";
show "  GET  /catalog/fields";
show "  GET  /catalog/filter-options";
show "  POST /query/table";
show "  POST /query/trend";
show "========================================";
show "";
