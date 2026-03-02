/ server_init.q
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

/ Stubs so app config.q loads cleanly in server context
if[not `orchestrator in key `.;
  .orchestrator.addSources:{[x]};
  .orchestrator.registerApp:{[x;y]}];

if[not `ingestionLog in key `.;
  .ingestionLog.init:{[]};
  .ingestionLog.markCompleted:{[a;b;c;d]};
  .ingestionLog.markFailed:{[a;b;c]}];

/ ============================================================================
/ DOMAIN CONFIG LOADER
/ ============================================================================

loadDomainConfigs:{[dom]
  domainPath:ROOT,"/apps/",string dom;
  if[() ~ @[key; hsym `$domainPath; {[e] ()}];
    show "Domain path not found: ",domainPath; :()];
  entries:key hsym `$domainPath;
  entries:entries where not null entries;
  entries:entries where not entries in `.gitkeep`server.q;
  {[domainPath; entry]
    configFile:domainPath,"/",string[entry],"/config.q";
    if[not () ~ @[key; hsym `$configFile; {[e] ()}];
      show "  Loading ",configFile;
      @[system; "l ",configFile; {[e] show "    [WARN] Failed: ",e}]];
  }[domainPath] each entries;
 }

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
