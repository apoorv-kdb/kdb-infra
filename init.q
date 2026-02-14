/ init.q
/ Single entry point for the infrastructure framework
/ Loads all modules in dependency order and initializes the system
/
/ Usage:
/   Prod:          q init.q -p 9000 -dbPath /data/databases/prod -archivePath /data/archive
/   Prod parallel: q init.q -p 8000 -dbPath /data/databases/prod_parallel -archivePath /data/archive
/                           -dailyRetention 90 -monthlyRetention 90
/
/ Command line args:
/   -p              port (standard q flag)
/   -dbPath         path to partitioned database (default: curated_db)
/   -archivePath    path to CSV archive directory (default: /data/archive)
/   -timerInterval  orchestrator interval in ms (default: 3600000 = 1 hour)
/   -dailyRetention days to keep daily partitions (default: 365)
/   -monthlyRetention days to keep monthly snapshots (default: 730)

/ ============================================================================
/ PARSE COMMAND LINE ARGS
/ ============================================================================

opts:.Q.opt .z.x;

argDbPath:$[`dbPath in key opts; hsym `$first opts`dbPath; `:curated_db];
argArchivePath:$[`archivePath in key opts; hsym `$first opts`archivePath; `:/data/archive];
argTimerInterval:$[`timerInterval in key opts; "J"$first opts`timerInterval; 3600000];
argDailyRetention:$[`dailyRetention in key opts; "J"$first opts`dailyRetention; 365];
argMonthlyRetention:$[`monthlyRetention in key opts; "J"$first opts`monthlyRetention; 730];

/ ============================================================================
/ LOAD MODULES IN DEPENDENCY ORDER
/ ============================================================================

show "========================================";
show "Loading KDB+ Infrastructure Framework";
show "========================================";

show "Loading core/validator.q";
\l core/validator.q

show "Loading core/ingestion_log.q";
\l core/ingestion_log.q

show "Loading core/csv_loader.q";
\l core/csv_loader.q

show "Loading core/db_writer.q";
\l core/db_writer.q

show "Loading sources.q";
\l sources.q

show "Loading schemas...";
schemaFiles:key `:schemas;
schemaFiles:schemaFiles where schemaFiles like "*.q";
{show "  Loading schemas/",string x; system "l schemas/",string x} each schemaFiles;

show "Loading monitoring/monitoring.q";
\l monitoring/monitoring.q

show "Loading orchestration/orchestrator.q";
\l orchestration/orchestrator.q

show "Loading maintenance/retention_manager.q";
\l maintenance/retention_manager.q

/ ============================================================================
/ INITIALIZE
/ ============================================================================

.dbWriter.setDbPath[argDbPath];
@[{system "mkdir -p ",1 _ string x}; argDbPath; {[e]}];

show "Initializing ingestion log...";
.ingestionLog.init[];
@[.ingestionLog.reload; argDbPath; {[e] show "No prior ingestion_log found, starting fresh"}];

.orchestrator.setInterval[argTimerInterval];
.orchestrator.setArchivePath[argArchivePath];
@[{system "mkdir -p ",1 _ string x}; argArchivePath; {[e]}];

.retention.setDailyRetention[argDailyRetention];
.retention.setMonthlyRetention[argMonthlyRetention];

.dbWriter.addDomain[`infra];

/ ============================================================================
/ STARTUP SUMMARY
/ ============================================================================

show "";
show "========================================";
show "Infrastructure loaded successfully";
show "========================================";
show "Database:          ",string argDbPath;
show "Archive:           ",string argArchivePath;
show "Timer interval:    ",string[argTimerInterval],"ms";
show "Daily retention:   ",string[argDailyRetention]," days";
show "Monthly retention: ",string[argMonthlyRetention]," days";
show "Sources configured:",string count source_config;
show "Schemas registered:",string count .validator.schemas;
show "========================================";
show "";
show "Next steps:";
show "  1. Register app domains:";
show "     .dbWriter.addDomain[`mydom]";
show "  2. Load app code:";
show "     \\l ../apps/myapp/data_refresh.q";
show "  3. Register app with orchestrator:";
show "     .orchestrator.registerApp[`myapp; .myapp.refresh]";
show "  4. Start orchestrator:";
show "     .orchestrator.start[]";
