/ server/server_init.q
/ Loads core infrastructure only.
/ Each app server explicitly loads what it needs beyond this baseline.
/ Dependencies: none

ROOT:rtrim ssr[{$[10h=type x;x;first x]} system "cd"; "\\"; "/"]

opts:.Q.opt .z.x;
/ dbPath must be passed explicitly or defaults to external data folder.
/ Data lives OUTSIDE the code folder by design — never under ROOT.
/ Override: -dbPath C:/data/databases/prod_parallel
argDbPath:$[`dbPath in key opts; hsym `$first opts`dbPath; `$"C:/data/databases/prod_parallel"];

show "========================================";
show "Loading Server Infrastructure";
show "  ROOT: ",ROOT;
show "========================================";

/ Core
system "l ",ROOT,"/core/db_writer.q";
system "l ",ROOT,"/core/csv_loader.q";
system "l ",ROOT,"/core/ingestion_log.q";

/ Essential lib — catalog, filters, dates (always needed)
system "l ",ROOT,"/lib/catalog.q";
system "l ",ROOT,"/lib/filters.q";
system "l ",ROOT,"/lib/dates.q";

/ Server infrastructure
system "l ",ROOT,"/server/cache.q";
system "l ",ROOT,"/server/http.q";

/ ============================================================================
/ INIT
/ ============================================================================

.dbWriter.setDbPath[argDbPath];

show "";
show "========================================";
show "Server infrastructure ready";
show "  ROOT:     ",ROOT;
show "  Database: ",string argDbPath;
show "  Port:     ",string system "p";
show "========================================";
show "";
