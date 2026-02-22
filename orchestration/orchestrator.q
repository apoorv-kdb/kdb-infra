/ orchestrator.q
/ Central coordination loop: scan, filter, group, dependency check, dispatch
/ Runs on .z.ts timer at configurable interval
/ Dependencies: csv_loader.q, ingestion_log.q, db_writer.q, monitoring.q

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Source configuration table - populated by app config.q via addSources
.orchestrator.source_config:([]
  source:`symbol$();
  app:`symbol$();
  required:`boolean$();
  directory:`symbol$();
  filePattern:`symbol$();
  delimiter:`char$();
  frequency:`symbol$()
 );

/ App registry: app name -> refresh function
.orchestrator.appRegistry:()!()

/ Timer interval in ms (default 1 hour)
.orchestrator.timerInterval:3600000

/ Run state
.orchestrator.isRunning:0b
.orchestrator.runCount:0

/ ============================================================================
/ SOURCE REGISTRATION (called by app config.q)
/ ============================================================================

.orchestrator.addSources:{[sourceList]
  if[99h = type sourceList; sourceList:enlist sourceList];
  `.orchestrator.source_config upsert sourceList;
 }

/ ============================================================================
/ APP REGISTRATION
/ ============================================================================

.orchestrator.registerApp:{[appName; refreshFn]
  .orchestrator.appRegistry[appName]:refreshFn;
 }

/ ============================================================================
/ FILE SCANNING
/ ============================================================================

/ Scan all source directories for files matching patterns
/ Returns: table of (source; date; filepath)
.orchestrator.scanAllSources:{[]
  results:([] source:`symbol$(); date:`date$(); filepath:`symbol$());

  {[results; idx]
    row:.orchestrator.source_config idx;
    dir:row`directory;
    pattern:row`filePattern;
    src:row`source;

    files:@[key; dir; {[e] `symbol$()}];
    if[0 = count files; :results];

    matched:files where files like string pattern;
    if[0 = count matched; :results];

    {[results; src; dir; fn]
      dt:.orchestrator.extractDate[fn];
      if[not null dt;
        fp:` sv dir , fn;
        :results , ([] source:enlist src; date:enlist dt; filepath:enlist fp)];
      results
    }[; src; dir]/[results; matched]
  }/[results; til count .orchestrator.source_config]
 }

/ Extract date from filename
/ Supports: YYYY-MM-DD, YYYY_MM_DD, YYYY.MM.DD, YYYYMMDD
.orchestrator.extractDate:{[filename]
  fn:string filename;
  n:count fn;

  / Try YYYY-MM-DD, YYYY_MM_DD, YYYY.MM.DD anywhere in filename
  i:0;
  while[i <= n - 10;
    if[all fn[i + 0 1 2 3] in "0123456789";
      if[fn[i+4] in "-_.";
        if[all fn[i + 5 6] in "0123456789";
          if[fn[i+7] = fn[i+4];
            if[all fn[i + 8 9] in "0123456789";
              dt:@["D"$; fn i + til 10; 0Nd];
              if[not null dt; :dt]]]]]];
    i+:1];

  / Try YYYYMMDD (8 consecutive digits)
  i:0;
  while[i <= n - 8;
    if[all fn[i + til 8] in "0123456789";
      c:fn i + til 8;
      dt:@["D"$; c[0 1 2 3],"-",c[4 5],"-",c[6 7]; 0Nd];
      if[not null dt; :dt]];
    i+:1];

  0Nd
 }

/ ============================================================================
/ WORK IDENTIFICATION
/ ============================================================================

.orchestrator.identifyWork:{[scanned]
  select from scanned where not .ingestionLog.isProcessed'[source; date]
 }

.orchestrator.groupByApp:{[work]
  work:work lj `source xkey select source, app, required from .orchestrator.source_config;
  select sources:source, filepaths:filepath, requiredSources:source where required
    by app, date from work
 }

.orchestrator.dependenciesMet:{[appName; dt; currentSources]
  requiredAll:exec source from .orchestrator.source_config where app = appName, required;
  previouslyDone:.ingestionLog.completedSources[dt];
  available:distinct currentSources , previouslyDone;
  all requiredAll in available
 }

/ ============================================================================
/ MAIN ORCHESTRATION LOOP
/ ============================================================================

.orchestrator.orchestratorRun:{[]
  if[.orchestrator.isRunning;
    show "Orchestrator already running - skipping tick";
    :()];
  `.orchestrator.isRunning set 1b;
  `.orchestrator.runCount set .orchestrator.runCount + 1;

  show "----------------------------------------";
  show "Orchestrator tick #",string[.orchestrator.runCount]," at ",string .z.p;

  / Phase 1: Scan for files
  show "[1/4] Scanning sources...";
  scanned:@[.orchestrator.scanAllSources; ::;
    {[e]
      show "  [ERROR] Scan failed: ",e;
      ([] source:`symbol$(); date:`date$(); filepath:`symbol$())}];
  show "  Found ",string[count scanned]," file(s)";

  / Phase 2: Identify new work
  show "[2/4] Identifying work...";
  work:@[.orchestrator.identifyWork; scanned;
    {[e]
      show "  [ERROR] Work identification failed: ",e;
      ([] source:`symbol$(); date:`date$(); filepath:`symbol$())}];
  show "  New work items: ",string count work;

  if[0 < count work;
    / Phase 3: Group by app and date, dispatch
    show "[3/4] Dispatching apps...";
    grouped:@[.orchestrator.groupByApp; work;
      {[e]
        show "  [ERROR] Grouping failed: ",e;
        ([] app:`symbol$(); date:`date$(); sources:(); filepaths:(); requiredSources:())}];

    {[grouped; idx]
      row:(0!grouped) idx;
      appName:row`app;
      dt:row`date;
      srcs:raze row`sources;
      fps:raze row`filepaths;

      if[.orchestrator.dependenciesMet[appName; dt; srcs];
        show "  Dispatching ",string[appName]," for ",string dt;
        sourceMap:srcs!fps;
        .orchestrator.dispatchApp[appName; dt; sourceMap]];
    }[grouped] each til count grouped;
  ];

  / Phase 4: Persist ingestion log
  show "[4/4] Persisting ingestion log...";
  @[.ingestionLog.persist; ::;
    {[e] show "  [ERROR] Log persist failed: ",e}];

  / Monitoring
  @[.monitoring.checkAll; ::;
    {[e] show "  [WARN] Monitoring check failed: ",e}];

  show "Tick complete.";
  show "----------------------------------------";

  `.orchestrator.isRunning set 0b;
 }

/ ============================================================================
/ APP DISPATCH
/ ============================================================================

.orchestrator.dispatchApp:{[appName; dt; sourceMap]
  if[not appName in key .orchestrator.appRegistry;
    show "  [ERROR] No refresh function registered for app: ",string appName;
    :()];

  refreshFn:.orchestrator.appRegistry appName;

  {[dt; src; fp]
    .ingestionLog.markProcessing[src; dt; fp];
  }[dt]'[key sourceMap; value sourceMap];

  result:.[refreshFn; (dt; sourceMap); {[e] "REFRESH_ERROR:",e}];

  if[10h = abs type result;
    show "  [ERROR] ",string[appName]," failed for ",string[dt],": ",result;
    {[dt; result; src] .ingestionLog.markFailed[src; dt; result]}[dt; result] each key sourceMap;
    :()];

  totalRows:{[dt; src]
    tblPath:` sv (.dbWriter.dbPath; `$string dt; src);
    $[() ~ @[key; tblPath; {[e] ()}]; 0j; `long$count get tblPath]
  }[dt] each key sourceMap;
  totalRows:sum totalRows;

  {[dt; recCount; src]
    .ingestionLog.markCompleted[src; dt; recCount];
  }[dt; totalRows] each key sourceMap;

  show "  [OK] ",string[appName]," completed for ",string[dt],
    " (",string[totalRows]," total rows)";
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
  if[0 < system "t"; system "t ",string ms];
 }

/ ============================================================================
/ MANUAL OPERATIONS
/ ============================================================================

.orchestrator.manualRefresh:{[appName; dt]
  allSources:exec source from .orchestrator.source_config where app = appName;
  fps:{[src; dt]
    dir:first exec directory from .orchestrator.source_config where source = src;
    pat:first exec filePattern from .orchestrator.source_config where source = src;
    files:@[key; dir; {[e] `symbol$()}];
    matched:files where files like string pat;
    dateMatched:matched where dt = .orchestrator.extractDate each matched;
    if[0 = count dateMatched; :()];
    ` sv dir , first dateMatched
  }[; dt] each allSources;
  sourceMap:allSources!fps;
  sourceMap:sourceMap where not (::) ~/: value sourceMap;
  .orchestrator.dispatchApp[appName; dt; sourceMap];
 }

.orchestrator.status:{[]
  `isRunning`runCount`timerInterval`registeredApps`registeredSources!(
    .orchestrator.isRunning;
    .orchestrator.runCount;
    .orchestrator.timerInterval;
    key .orchestrator.appRegistry;
    count .orchestrator.source_config)
 }

/ Reset a source+date so it will be reprocessed on the next tick
/ Removes only this source's row from the persisted log - other sources for the same date are unaffected
/ The DB data partitions (e.g. sales_transactions) are left intact - writePartition overwrites them
/ Usage: .orchestrator.resetSource[`sales_transactions; 2024.02.12]
.orchestrator.resetSource:{[src; dt]
  / Remove from in-memory log
  delete from `.ingestionLog.tbl where source = src, date = dt;

  / Remove just this source's row from the persisted partition
  logPath:` sv (.dbWriter.dbPath; `$string dt; `infra_ingestion_log);
  .[{[lp; src]
    existing:get lp;
    updated:delete from existing where source = src;
    lp set updated
  }; (logPath; src);
  {[e] show "  [WARN] Could not update persisted log (may not exist yet): ",e}];

  show "Reset complete - ",string[src]," for ",string[dt]," will reprocess on next tick";
 }
