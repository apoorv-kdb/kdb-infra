/ orchestrator.q
/ Central coordination loop: scan, filter, group, dependency check, dispatch
/ Runs on .z.ts timer at configurable interval
/
/ Dependencies: csv_loader.q, ingestion_log.q, db_writer.q, monitoring.q

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Source configuration table — populated by app config.q via addSources
.orchestrator.source_config:([]
  source:`symbol$();
  app:`symbol$();
  required:`boolean$();
  directory:`symbol$();
  filePattern:();
  delimiter:`char$();
  frequency:`symbol$()
 );

/ App registry: app name -> refresh function
.orchestrator.appRegistry:()!()

/ Archive path for processed CSVs
.orchestrator.archivePath:`:/data/archive

/ Timer interval in ms (default 1 hour)
.orchestrator.timerInterval:3600000

/ Run state
.orchestrator.isRunning:0b
.orchestrator.runCount:0

/ ============================================================================
/ SOURCE REGISTRATION (called by app config.q)
/ ============================================================================

/ Register source entries at runtime
/ Args: sourceList - dict (single source) or table (multiple sources)
.orchestrator.addSources:{[sourceList]
  if[99h = type sourceList; sourceList:enlist sourceList];
  `.orchestrator.source_config upsert sourceList;
 }

/ ============================================================================
/ APP REGISTRATION
/ ============================================================================

/ Register an app's data refresh function
/ Args:
/   appName: symbol - app name (must match app column in source_config)
/   refreshFn: function - signature: {[date; availableSources] ...}
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

    matched:files where files like pattern;
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

/ Filter scanned files to only new or previously-failed work
.orchestrator.identifyWork:{[scanned]
  select from scanned where not .ingestionLog.isProcessed'[source; date]
 }

/ Group new work by app and date
.orchestrator.groupByApp:{[work]
  work:work lj `source xkey select source, app, required from .orchestrator.source_config;
  select sources:source, filepaths:filepath, requiredSources:source where required
    by app, date from work
 }

/ Check if all required sources for an app/date are available
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
  if[.orchestrator.isRunning; :()];
  `.orchestrator.isRunning set 1b;
  `.orchestrator.runCount set .orchestrator.runCount + 1;

  tickStart:.z.p;

  / Phase 1: Scan for files
  scanned:@[.orchestrator.scanAllSources; ::;
    {[e] show "Scan error: ",e; ([] source:`symbol$(); date:`date$(); filepath:`symbol$())}];

  / Phase 2: Identify new work
  work:.orchestrator.identifyWork scanned;

  if[0 < count work;
    / Phase 3: Group by app and date
    grouped:.orchestrator.groupByApp work;

    / Phase 4+5: Check dependencies and dispatch
    {[grouped; idx]
      row:(0!grouped) idx;
      appName:row`app;
      dt:row`date;
      srcs:row`sources;
      fps:row`filepaths;

      if[.orchestrator.dependenciesMet[appName; dt; srcs];
        sourceMap:srcs!fps;
        .orchestrator.dispatchApp[appName; dt; sourceMap]];
    }[grouped] each til count grouped;
  ];

  / Phase 6: Persist ingestion log
  .ingestionLog.persist[];

  / Phase 7: Archive processed CSVs
  .orchestrator.archiveCompleted[tickStart];

  / Phase 8: Monitoring
  @[.monitoring.checkAll; ::; {[e] show "Monitoring error: ",e}];

  `.orchestrator.isRunning set 0b;
 }

/ ============================================================================
/ APP DISPATCH
/ ============================================================================

/ Call an app's registered refresh function
.orchestrator.dispatchApp:{[appName; dt; sourceMap]
  if[not appName in key .orchestrator.appRegistry;
    show "No refresh function registered for app: ",string appName;
    :()];

  refreshFn:.orchestrator.appRegistry appName;

  / Mark all sources as processing
  {[dt; src; fp]
    .ingestionLog.markProcessing[src; dt; fp];
  }[dt]'[key sourceMap; value sourceMap];

  / Call the app's refresh function
  result:@[refreshFn; (dt; sourceMap);
    {[e] show "App refresh failed: ",e; `error}];

  if[`error ~ result;
    {[dt; src]
      .ingestionLog.markFailed[src; dt; "App refresh failed"];
    }[dt] each key sourceMap;
    :()];

  / Mark sources as completed
  {[dt; src]
    .ingestionLog.markCompleted[src; dt; 0];
  }[dt] each key sourceMap;
 }

/ ============================================================================
/ CSV ARCHIVING
/ ============================================================================

/ Archive CSV files that were successfully processed during this tick
.orchestrator.archiveCompleted:{[tickStart]
  completed:@[.ingestionLog.completedSince; tickStart;
    {[e] ([] filepath:`symbol$(); date:`date$())}];
  if[0 = count completed; :()];

  {[completed; idx]
    row:completed idx;
    fp:row`filepath;
    dt:row`date;

    / Build archive destination: archivePath/YYYY/MM/filename
    yr:string `year$dt;
    mn:$[10 > `mm$dt; "0",""; ""],string `mm$dt;
    destDir:` sv .orchestrator.archivePath , `$yr , `$mn;

    @[{system "mkdir -p ",1 _ string x}; destDir; {[e]}];

    fname:last "/" vs string fp;
    destFile:` sv destDir , `$fname;

    @[{[src; dest] system "mv ",src," ",dest}; (1 _ string fp; 1 _ string destFile);
      {[e] show "Archive failed: ",e}];
  }[completed] each til count completed;
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

.orchestrator.setArchivePath:{[path]
  `.orchestrator.archivePath set path;
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
    matched:files where files like pat;
    dateMatched:matched where dt = .orchestrator.extractDate each matched;
    if[0 = count dateMatched; :()];
    ` sv dir , first dateMatched
  }[; dt] each allSources;
  sourceMap:allSources!fps;
  sourceMap:sourceMap where not (::) ~/: value sourceMap;
  .orchestrator.dispatchApp[appName; dt; sourceMap];
 }

.orchestrator.backfill:{[appName; startDate; endDate]
  dates:startDate + til 1 + endDate - startDate;
  {[appName; dt] .orchestrator.manualRefresh[appName; dt]}[appName] each dates;
 }

.orchestrator.status:{[]
  `isRunning`runCount`timerInterval`registeredApps`registeredSources`archivePath!(
    .orchestrator.isRunning;
    .orchestrator.runCount;
    .orchestrator.timerInterval;
    key .orchestrator.appRegistry;
    count .orchestrator.source_config;
    .orchestrator.archivePath)
 }
