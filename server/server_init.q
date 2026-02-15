/ server_init.q
/ Entry point for domain server processes (NOT the orchestrator)
/ Loads: validator, db_writer, lib, cache
/ Also loads all app config.q files for a given domain so schemas are available
/
/ Usage:
/   q apps/sales/server.q -p 5001 -dbPath /data/databases/prod
/
/ Each domain's server.q starts with: \l server/server_init.q

/ ============================================================================
/ ROOT DIRECTORY
/ ============================================================================

ROOT:first system "pwd"

/ ============================================================================
/ PARSE COMMAND LINE ARGS
/ ============================================================================

opts:.Q.opt .z.x;

argDbPath:$[`dbPath in key opts; hsym `$first opts`dbPath; hsym `$ROOT,"/curated_db"];
argDomain:$[`domain in key opts; `$first opts`domain; `];

/ ============================================================================
/ LOAD MODULES
/ ============================================================================

show "========================================";
show "Loading Server Infrastructure";
show "ROOT: ",ROOT;
show "========================================";

/ --- Core (only what servers need) ---
show "Loading core/validator.q";
system "l ",ROOT,"/core/validator.q";

show "Loading core/db_writer.q";
system "l ",ROOT,"/core/db_writer.q";

/ --- Library (shared transformations) ---
show "Loading lib...";
libPath:ROOT,"/lib";
libFiles:@[key; hsym `$libPath; {[e] `$()}];
libFiles:libFiles where libFiles like "*.q";
{[libPath; f] show "  Loading lib/",string f; system "l ",libPath,"/",string f}[libPath] each libFiles;

/ --- Cache ---
show "Loading server/cache.q";
system "l ",ROOT,"/server/cache.q";

/ ============================================================================
/ STUBS — so app config.q loads cleanly in server context
/ ============================================================================

if[not `orchestrator in key `.;
  .orchestrator.addSources:{[x]};
  .orchestrator.registerApp:{[x;y]}];

if[not `retention in key `.;
  .retention.classifyBatch:{[x]};
  .retention.setDailyRetention:{[x]};
  .retention.setMonthlyRetention:{[x]}];

/ ============================================================================
/ LOAD DOMAIN APP CONFIGS (for schemas + domain registration)
/ ============================================================================

loadDomainConfigs:{[domain]
  domainPath:ROOT,"/apps/",string domain;
  if[() ~ @[key; hsym `$domainPath; {[e] ()}];
    show "Domain path not found: ",domainPath;
    :()];

  entries:key hsym `$domainPath;
  entries:entries where not entries in `` `.gitkeep`server.q;

  {[domainPath; entry]
    configFile:domainPath,"/",string[entry],"/config.q";
    if[not () ~ @[key; hsym `$configFile; {[e] ()}];
      show "  Loading ",configFile;
      @[system; "l ",configFile; {[e] show "    [WARN] Failed: ",e}]];
  }[domainPath] each entries;
 }

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
show "ROOT:            ",ROOT;
show "Database:        ",string argDbPath;
show "Port:            ",string system "p";
show "Lib modules:     ",string count libFiles;
show "========================================";
show "";
