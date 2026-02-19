/ init.q
/ Entry point for the orchestrator process
/ Usage:
/   Prod:          q init.q -p 9000 -dbPath /data/databases/prod
/   Prod parallel: q init.q -p 8000
/   Custom:        q init.q -p 8000 -dbPath /data/databases/custom

/ ============================================================================
/ ROOT DIRECTORY
/ ============================================================================

ROOT:rtrim ssr[first system $[.z.o like "w*"; "echo %CD%"; "pwd"]; "\\"; "/"]

/ ============================================================================
/ PARSE COMMAND LINE ARGS
/ ============================================================================

opts:.Q.opt .z.x;

argDbPath:$[`dbPath in key opts; hsym `$first opts`dbPath; `:/data/databases/prod_parallel];
argTimerInterval:$[`timerInterval in key opts; "J"$first opts`timerInterval; 3600000];

/ ============================================================================
/ LOAD MODULES IN DEPENDENCY ORDER
/ ============================================================================

show "========================================";
show "Loading KDB+ Infrastructure Framework";
show "ROOT: ",ROOT;
show "========================================";

/ --- Layer 1: No dependencies ---
show "Loading core/validator.q";
system "l ",ROOT,"/core/validator.q";

show "Loading core/ingestion_log.q";
system "l ",ROOT,"/core/ingestion_log.q";

/ --- Layer 2: Depends on Layer 1 ---
show "Loading core/csv_loader.q";
system "l ",ROOT,"/core/csv_loader.q";

show "Loading core/db_writer.q";
system "l ",ROOT,"/core/db_writer.q";

/ --- Layer 3: Depends on core ---
show "Loading monitoring/monitoring.q";
system "l ",ROOT,"/monitoring/monitoring.q";

show "Loading orchestration/orchestrator.q";
system "l ",ROOT,"/orchestration/orchestrator.q";

/ ============================================================================
/ LOAD APPS - walk apps/{domain}/{app}/, load each config.q + data_refresh.q
/ ============================================================================

show "";
show "Loading apps...";
appRoot:hsym `$ROOT,"/apps";
domains:key appRoot;
domains:domains where not null domains;
domains:domains where not domains in `.gitkeep;

{[dom]
  domainPath:ROOT,"/apps/",string dom;
  entries:key hsym `$domainPath;
  entries:entries where not null entries;
  entries:entries where not entries in `.gitkeep;

  {[domainPath; entry]
    entryPath:domainPath,"/",string entry;
    configFile:entryPath,"/config.q";
    refreshFile:entryPath,"/data_refresh.q";

    if[not () ~ @[key; hsym `$configFile; {[e] ()}];
      if[not () ~ @[key; hsym `$refreshFile; {[e] ()}];
        show "  Loading ",refreshFile;
        @[system; "l ",refreshFile; {[e] show "    [WARN] Failed: ",e}]];
      show "  Loading ",configFile;
      @[system; "l ",configFile; {[e] show "    [WARN] Failed: ",e}]];
  }[domainPath] each entries;
 } each domains;

/ ============================================================================
/ INITIALIZE
/ ============================================================================

.ingestionLog.init[];
.dbWriter.setDbPath[argDbPath];
.dbWriter.addDomain[`infra];

.orchestrator.setInterval[argTimerInterval];

.ingestionLog.reload[argDbPath];

@[{system $[.z.o like "w*"; "mkdir \"",ssr[1 _ string x; "/"; "\\"],"\""; "mkdir -p ",1 _ string x]}; argDbPath; {[e]}];

/ ============================================================================
/ STARTUP SUMMARY
/ ============================================================================

show "";
show "========================================";
show "Infrastructure loaded successfully";
show "========================================";
show "ROOT:              ",ROOT;
show "Database path:     ",string argDbPath;
show "Timer interval:    ",string[argTimerInterval],"ms";
show "Sources registered:",string count .orchestrator.source_config;
show "Schemas registered:",string count .validator.schemas;
show "Apps registered:   ",string count .orchestrator.appRegistry;
show "========================================";
show "";
show "Next steps:";
show "  Start orchestrator:  .orchestrator.start[]";
show "  Or run once:         .orchestrator.orchestratorRun[]";
