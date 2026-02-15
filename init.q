/ init.q
/ Entry point for the orchestrator process
/ For domain query servers, use server/server_init.q instead
/
/ Usage:
/   Prod:          q init.q -p 9000 -dbPath /data/databases/prod -archivePath /data/archive
/   Prod parallel: q init.q -p 8000 -dbPath /data/databases/prod_parallel -archivePath /data/archive
/                           -dailyRetention 90 -monthlyRetention 90
/
/ Command line args:
/   -p              port (standard q flag)
/   -dbPath         path to partitioned database (default: {ROOT}/curated_db)
/   -archivePath    path to CSV archive directory (default: {ROOT}/archive)
/   -timerInterval  orchestrator interval in ms (default: 3600000 = 1 hour)
/   -dailyRetention days to keep daily partitions (default: 365)
/   -monthlyRetention days to keep monthly snapshots (default: 730)

/ ============================================================================
/ ROOT DIRECTORY
/ ============================================================================

ROOT:first system "pwd"

/ ============================================================================
/ PARSE COMMAND LINE ARGS
/ ============================================================================

opts:.Q.opt .z.x;

argDbPath:$[`dbPath in key opts; hsym `$first opts`dbPath; hsym `$ROOT,"/curated_db"];
argArchivePath:$[`archivePath in key opts; hsym `$first opts`archivePath; hsym `$ROOT,"/archive"];
argTimerInterval:$[`timerInterval in key opts; "J"$first opts`timerInterval; 3600000];
argDailyRetention:$[`dailyRetention in key opts; "J"$first opts`dailyRetention; 365];
argMonthlyRetention:$[`monthlyRetention in key opts; "J"$first opts`monthlyRetention; 730];

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

show "Loading maintenance/retention_manager.q";
system "l ",ROOT,"/maintenance/retention_manager.q";

/ ============================================================================
/ LOAD APPS — walk apps/{domain}/{app}/, load each config.q + data_refresh.q
/ ============================================================================

show "";
show "Loading apps...";
appRoot:hsym `$ROOT,"/apps";
domains:key appRoot;
domains:domains where not domains in `` `.gitkeep;

{[domain]
  domainPath:ROOT,"/apps/",string domain;
  entries:key hsym `$domainPath;
  entries:entries where not entries in `` `.gitkeep;

  / Load each subdirectory that has a config.q (these are apps)
  {[domainPath; entry]
    entryPath:domainPath,"/",string entry;

    / Skip files (like server.q) — only process directories
    configFile:entryPath,"/config.q";
    refreshFile:entryPath,"/data_refresh.q";

    if[not () ~ @[key; hsym `$configFile; {[e] ()}];
      / Load data_refresh first (defines the function config.q registers)
      if[not () ~ @[key; hsym `$refreshFile; {[e] ()}];
        show "  Loading ",refreshFile;
        @[system; "l ",refreshFile; {[e] show "    [WARN] Failed: ",e}]];

      / Load config (registers sources, schemas, retention, app)
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

.orchestrator.setArchivePath[argArchivePath];
.orchestrator.setInterval[argTimerInterval];
.retention.setDailyRetention[argDailyRetention];
.retention.setMonthlyRetention[argMonthlyRetention];

.ingestionLog.reload[argDbPath];

@[{system "mkdir -p ",1 _ string x}; argDbPath; {[e]}];
@[{system "mkdir -p ",1 _ string x}; argArchivePath; {[e]}];

/ ============================================================================
/ STARTUP SUMMARY
/ ============================================================================

show "";
show "========================================";
show "Infrastructure loaded successfully";
show "ROOT:              ",ROOT;
show "Database path:     ",string argDbPath;
show "Archive path:      ",string argArchivePath;
show "Timer interval:    ",string[argTimerInterval],"ms";
show "Sources registered:",string count .orchestrator.source_config;
show "Schemas registered:",string count .validator.schemas;
show "Apps registered:   ",string count .orchestrator.appRegistry;
show "========================================";
show "";
show "Next steps:";
show "  Start orchestrator:  .orchestrator.start[]";
show "  Or run manually:     .orchestrator.run[]";
