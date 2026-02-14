/ server_init.q
/ Entry point for server processes
/ Loads the minimal set of infrastructure needed for serving:
/   - core/validator.q (schema lookups)
/   - core/db_writer.q (database access)
/   - lib/*.q (shared transformation functions)
/   - server/cache.q (cache management)
/
/ Does NOT load: orchestrator, monitoring, retention, ingestion_log, sources
/
/ Usage:
/   q server/server_init.q -p 9001 -dbPath /data/databases/prod
/
/ Then in your server code:
/   \l server/server_init.q
/   .cache.register[`my_view; `funding_collateral_by_currency; 365; ::]
/   .cache.loadAll[]
/
/ Command line args:
/   -p         port (standard q flag)
/   -dbPath    path to partitioned database (default: curated_db)

/ ============================================================================
/ PARSE COMMAND LINE ARGS
/ ============================================================================

opts:.Q.opt .z.x;

argDbPath:$[`dbPath in key opts; hsym `$first opts`dbPath; `:curated_db];

/ ============================================================================
/ LOAD MODULES
/ ============================================================================

show "========================================";
show "Loading Server Infrastructure";
show "========================================";

/ --- Core (only what servers need) ---
show "Loading core/validator.q";
\l core/validator.q

show "Loading core/db_writer.q";
\l core/db_writer.q

/ --- Schemas (so validator has schema info) ---
show "Loading schemas...";
schemaFiles:@[key; `:schemas; {[e] `$()}];
schemaFiles:schemaFiles where schemaFiles like "*.q";
{show "  Loading schemas/",string x; system "l schemas/",string x} each schemaFiles;

/ --- Library (shared transformations) ---
show "Loading lib...";
libFiles:@[key; `:lib; {[e] `$()}];
libFiles:libFiles where libFiles like "*.q";
{show "  Loading lib/",string x; system "l lib/",string x} each libFiles;

/ --- Cache ---
show "Loading server/cache.q";
\l server/cache.q

/ ============================================================================
/ INITIALIZE
/ ============================================================================

.dbWriter.setDbPath[argDbPath];

/ ============================================================================
/ STARTUP SUMMARY
/ ============================================================================

show "";
show "========================================";
show "Server infrastructure ready";
show "========================================";
show "Database:        ",string argDbPath;
show "Port:            ",string system "p";
show "Schemas loaded:  ",string count .validator.schemas;
show "Lib modules:     ",string count libFiles;
show "========================================";
show "";
show "Next steps:";
show "  1. Register cached tables:";
show "     .cache.register[`name; `table; horizonDays; transformFn]";
show "  2. Load cache:";
show "     .cache.loadAll[]";
show "  3. Start refresh timer:";
show "     .cache.startRefresh[600000]";
