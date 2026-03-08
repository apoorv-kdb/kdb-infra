/ orchestration/orchestrator.q
/ Central coordination loop: discover, filter, group, dependency check, dispatch.
/ Runs on .z.ts timer at configurable interval.
/ Dependencies: csv_loader.q, ingestion_log.q, db_writer.q, lib/discovery.q
//
/ Source registration is now CSV-driven (config/sources_<app>.csv).
/ Each app's data_refresh/*.q files self-register via
/   .orchestrator.registerRefreshUnit[`unitname; .unit.refresh]
/ The orchestrator auto-discovers and loads those files at startup.

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Source configuration table — populated by .orchestrator.loadSourcesCsv at startup.
/ Columns match sources_<app>.csv plus an internal `app` tag.
.orchestrator.source_config:([]
  source:      `symbol$();
  refreshUnit: `symbol$();
  app:         `symbol$();
  required:    `boolean$();
  filePattern: `symbol$();
  dateFrom:    `symbol$();
  dateFormat:  ();
  dateDelim:   `char$();
  delimiter:   `char$()
 );

/ RefreshUnit registry: refreshUnit name -> refresh function
.orchestrator.refreshRegistry:()!()

/ Timer interval in ms (default 1 hour)
.orchestrator.timerInterval:3600000

/ Run state
.orchestrator.isRunning:0b
.orchestrator.runCount:0

/ ============================================================================
/ SOURCE REGISTRATION (called at startup via CSV load)
/ ============================================================================

/ Load a sources_<app>.csv file and upsert rows into source_config.
/ The app name is derived from the caller and tagged onto every row.
/ CSV schema: source,refreshUnit,filePattern,dateFrom,dateFormat,dateDelim,delimiter,required
.orchestrator.loadSourcesCsv:{[filePath; appName]
  raw:("SSSSSCCB"; enlist ",") 0: hsym `$filePath;
  / Parse required: "1"/"0" or "true"/"false" -> boolean
  reqCol:raw`required;
  n:count raw;
  rows:([]
    source:      raw`source;
    refreshUnit: raw`refreshUnit;
    app:         n#enlist appName;
    required:    reqCol;
    filePattern: raw`filePattern;
    dateFrom:    raw`dateFrom;
    dateFormat:  string each raw`dateFormat;
    dateDelim:   raw`dateDelim;
    delimiter:   raw`delimiter
  );
  `.orchestrator.source_config upsert rows;
 }

/ ============================================================================
/ REFRESH UNIT REGISTRATION (called from apps/*/data_refresh/*.q)
/ ============================================================================

.orchestrator.registerRefreshUnit:{[unitName; refreshFn]
  .orchestrator.refreshRegistry[unitName]:refreshFn;
 }

/ ============================================================================
/ WORK IDENTIFICATION (delegates to lib/discovery.q)
/ ============================================================================

.orchestrator.identifyWork:{[]
  csvPath:hsym `$argCsvPath;
  scanned:.discovery.identifyWork[.orchestrator.source_config; csvPath];
  / Filter out refreshUnit+date combos already completed
  select from scanned where not .ingestionLog.isProcessed'[refreshUnit; date]
 }

.orchestrator.groupByRefreshUnit:{[work]
  work:work lj `source xkey
    select source, refreshUnit, required from .orchestrator.source_config;
  select sources:source, filepaths:filepath, requiredSources:source where required
    by refreshUnit, date from work
 }

.orchestrator.dependenciesMet:{[ru; dt; currentSources]
  requiredAll:exec source from .orchestrator.source_config
    where refreshUnit=ru, required;
  all requiredAll in currentSources
 }

/ ============================================================================
/ MAIN ORCHESTRATION LOOP
/ ============================================================================

.orchestrator.orchestratorRun:{[]
  if[.orchestrator.isRunning;
    show "Orchestrator already running - skipping tick";
    :()];
  `.orchestrator.isRunning set 1b;
  `.orchestrator.runCount set .orchestrator.runCount+1;

  show "----------------------------------------";
  show "Orchestrator tick #",string[.orchestrator.runCount]," at ",string .z.p;

  / Phase 1: Discover work
  show "[1/4] Discovering work...";
  work:@[.orchestrator.identifyWork; ::;
    {[e]
      show "  [ERROR] Discovery failed: ",e;
      ([] source:`symbol$(); refreshUnit:`symbol$(); date:`date$(); filepath:`symbol$())}];
  show "  New work items: ",string count work;

  if[0<count work;
    / Phase 2: Group by refreshUnit and date
    show "[2/4] Grouping by refresh unit...";
    grouped:@[.orchestrator.groupByRefreshUnit; work;
      {[e]
        show "  [ERROR] Grouping failed: ",e;
        ([] refreshUnit:`symbol$(); date:`date$();
            sources:(); filepaths:(); requiredSources:())}];

    / Phase 3: Dispatch
    show "[3/4] Dispatching refresh units...";
    {[grouped; idx]
      row:(0!grouped) idx;
      ru: row`refreshUnit;
      dt: row`date;
      srcs:row`sources;
      fps: row`filepaths;
      if[.orchestrator.dependenciesMet[ru; dt; srcs];
        show "  Dispatching ",string[ru]," for ",string dt;
        sourceMap:srcs!fps;
        .orchestrator.dispatchRefreshUnit[ru; dt; sourceMap]];
    }[grouped] each til count grouped;
  ];

  / Phase 4: Persist ingestion log
  show "[4/4] Persisting ingestion log...";
  @[.ingestionLog.persist; ::;
    {[e] show "  [ERROR] Log persist failed: ",string e}];

  show "Tick complete.";
  show "----------------------------------------";
  `.orchestrator.isRunning set 0b;
 }

/ ============================================================================
/ REFRESH UNIT DISPATCH
/ ============================================================================

.orchestrator.dispatchRefreshUnit:{[ru; dt; sourceMap]
  if[not ru in key .orchestrator.refreshRegistry;
    show "  [ERROR] No refresh function registered for refreshUnit: ",string ru;
    :()];

  refreshFn:.orchestrator.refreshRegistry ru;

  .ingestionLog.markProcessing[ru; dt];

  result:.[refreshFn; (dt; sourceMap); {[e] "REFRESH_ERROR:",e}];

  if[10h=abs type result;
    show "  [ERROR] ",string[ru]," failed for ",string[dt],": ",result;
    .ingestionLog.markFailed[ru; dt; result];
    :()];

  / Build tableCounts from partitions written by this refreshUnit's domain.
  / Domain is the app name — all tables for that app are prefixed with it.
  ruApp:first exec distinct app from .orchestrator.source_config
    where refreshUnit=ru;
  partPath:` sv (.dbWriter.dbPath; `$string dt);
  allTbls:@[key; partPath; {[e] `symbol$()}];
  domainTbls:allTbls where allTbls like (string[ruApp],"*");
  tableCounts:{[dp; dt; tbl]
    n:@[{`long$count get x}; ` sv (dp;`$string dt;tbl); {[e] 0j}];
    (enlist tbl)!enlist n
  }[.dbWriter.dbPath; dt;] each domainTbls;
  / Merge list of single-key dicts into one dict
  tableCounts:$[0=count tableCounts; ()!(); (,/) tableCounts];

  .ingestionLog.markCompleted[ru; dt; tableCounts; ""];

  tcStr:.ingestionLog.serialiseCounts[tableCounts];
  show "  [OK] ",string[ru]," completed for ",string[dt],
    $[0<count tcStr; " (",tcStr,")"; ""];
 }

/ ============================================================================
/ DRY RUN
/ ============================================================================

/ Print what would be dispatched for the given app without executing anything.
.orchestrator.dryRun:{[appName]
  show "DryRun: app=",string appName;
  csvPath:hsym `$argCsvPath;
  scanned:.discovery.identifyWork[.orchestrator.source_config; csvPath];
  / Scope to this app's refresh units
  appRUs:exec distinct refreshUnit from .orchestrator.source_config
    where app=appName;
  scanned:select from scanned where refreshUnit in appRUs;
  / Filter already-processed
  pending:select from scanned where not .ingestionLog.isProcessed'[refreshUnit; date];
  if[0=count pending;
    show "  (no pending work)";
    :()];
  grouped:.orchestrator.groupByRefreshUnit[pending];
  grouped:select from 0!grouped where refreshUnit in appRUs;
  {[row]
    ru: row`refreshUnit;
    dt: row`date;
    srcs:row`sources;
    fps: row`filepaths;
    depOk:.orchestrator.dependenciesMet[ru; dt; srcs];
    show "  [",($[depOk;"DISPATCH";"BLOCKED — missing required sources"]),"] ",
         string[ru]," | ",string[dt]," | sources: ",", " sv string srcs;
  } each grouped;
 }

/ ============================================================================
/ TIMER CONTROL
/ ============================================================================

.orchestrator.start:{[]
  .z.ts:{.orchestrator.orchestratorRun[]};
  system "t ",string .orchestrator.timerInterval;
  show "Orchestrator started. Interval: ",string[.orchestrator.timerInterval],"ms";
 }

.orchestrator.stop:{[]
  system "t 0";
  show "Orchestrator stopped.";
 }

.orchestrator.setInterval:{[ms]
  `.orchestrator.timerInterval set ms;
  if[0<system "t"; system "t ",string ms];
 }

/ ============================================================================
/ MANUAL OPERATIONS
/ ============================================================================

.orchestrator.manualRefresh:{[ru; dt]
  allSources:exec source from .orchestrator.source_config where refreshUnit=ru;
  csvPath:hsym `$argCsvPath;
  fps:{[csvPath; src; dt]
    pat:first exec filePattern from .orchestrator.source_config where source=src;
    frm:first exec dateFrom   from .orchestrator.source_config where source=src;
    fmt:first exec dateFormat  from .orchestrator.source_config where source=src;
    dlm:first exec dateDelim   from .orchestrator.source_config where source=src;
    files:@[key; csvPath; {[e] `symbol$()}];
    matched:files where files like string pat;
    dateMatched:$[frm=`filename;
      matched where dt=.discovery.extractDateFromFilename[fmt; dlm;] each string matched;
      matched where dt=.discovery.parseToken[fmt;] each string matched];
    if[0=count dateMatched; :()];
    ` sv csvPath,first dateMatched
  }[csvPath;; dt] each allSources;
  sourceMap:allSources!fps;
  sourceMap:sourceMap where not (::)~/: value sourceMap;
  .orchestrator.dispatchRefreshUnit[ru; dt; sourceMap];
 }

.orchestrator.status:{[]
  `isRunning`runCount`timerInterval`registeredRefreshUnits`registeredSources!(
    .orchestrator.isRunning;
    .orchestrator.runCount;
    .orchestrator.timerInterval;
    key .orchestrator.refreshRegistry;
    count .orchestrator.source_config)
 }

.orchestrator.resetSource:{[ru; dt]
  delete from `.ingestionLog.tbl where refreshUnit=ru, date=dt;
  logPath:` sv (.dbWriter.dbPath; `$string dt; `infra_ingestion_log);
  .[{[lp; ru]
    existing:get lp;
    updated:delete from existing where refreshUnit=ru;
    lp set updated
  }; (logPath; ru);
  {[e] show "  [WARN] Could not update persisted log (may not exist yet): ",string e}];
  show "Reset complete - ",string[ru]," for ",string[dt]," will reprocess on next tick";
 }

/ ============================================================================
/ STARTUP
/ ============================================================================

ROOT:rtrim ssr[{$[10h=type x;x;first x]} system "cd"; "\\"; "/"]

opts:.Q.opt .z.x;

argDbPath: $[`dbPath  in key opts; first opts`dbPath;  "C:/data/databases/prod_parallel"];
argCsvPath:$[`csvPath in key opts; first opts`csvPath; "C:/data/csv"];

show "========================================";
show "Loading Orchestrator";
show "  ROOT:    ",ROOT;
show "  DB:      ",argDbPath;
show "  CSV:     ",argCsvPath;
show "========================================";

/ Core infrastructure
system "l ",ROOT,"/core/db_writer.q";
system "l ",ROOT,"/core/csv_loader.q";
system "l ",ROOT,"/core/ingestion_log.q";

/ Lib
system "l ",ROOT,"/lib/catalog.q";
system "l ",ROOT,"/lib/filters.q";
system "l ",ROOT,"/lib/dates.q";
system "l ",ROOT,"/lib/discovery.q";

/ Set DB path and load ingestion log history
.dbWriter.setDbPath[hsym `$argDbPath];
.ingestionLog.reload[hsym `$argDbPath];

/ Auto-discover apps and load per-app files
appRoot:hsym `$ROOT,"/apps";
appList:@[{x where not null x}; key appRoot; {[e] `symbol$()}];

appIdx:0;
while[appIdx < count appList;
  app:appList appIdx;

  / Load catalog (app-local path first, then top-level config/)
  catFile: ROOT,"/apps/",string[app],"/config/catalog_",string[app],".csv";
  catFile2:ROOT,"/config/catalog_",string[app],".csv";
  catPath:$[not ()~@[key; hsym `$catFile;  {[e] ()}]; catFile;
             not ()~@[key; hsym `$catFile2; {[e] ()}]; catFile2; ""];
  if[0<count catPath;
    show "  Loading catalog: ",string app;
    .catalog.load[catPath; `$string app]];

  / Load all .q files in apps/<app>/data_refresh/ — system "l" must run at top level
  drRoot:hsym `$ROOT,"/apps/",string[app],"/data_refresh";
  drFiles:@[{x where x like "*.q"}; key drRoot; {[e] `symbol$()}];
  drIdx:0;
  while[drIdx < count drFiles;
    fp:ROOT,"/apps/",string[app],"/data_refresh/",string drFiles[drIdx];
    show "  Loading data_refresh: ",string[app],"/",string drFiles[drIdx];
    system "l ",fp;
    drIdx+:1];

  / Load sources CSV
  srcFile:ROOT,"/config/sources_",string[app],".csv";
  if[not ()~@[key; hsym `$srcFile; {[e] ()}];
    show "  Loading sources: ",string app;
    .orchestrator.loadSourcesCsv[srcFile; `$string app]];

  appIdx+:1];

show "";
show "========================================";
show "Orchestrator ready";
show "  DB:      ",argDbPath;
show "  CSV:     ",argCsvPath;
show "  RefreshUnits: ",", " sv string key .orchestrator.refreshRegistry;
show "  Sources:      ",string count .orchestrator.source_config;
show "========================================";
show "";

/ Wire timer then run one immediate tick
.z.ts:{.orchestrator.orchestratorRun[]};
system "t ",string .orchestrator.timerInterval;
show "Orchestrator started. Interval: ",string[.orchestrator.timerInterval],"ms";
show "Running initial scan...";
.orchestrator.orchestratorRun[];
