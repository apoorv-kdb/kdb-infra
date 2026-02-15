/ orchestrator.q
/ Central coordination loop: scan, filter, group, dependency check, dispatch
/ Runs on .z.ts timer at configurable interval
/
/ Dependencies: csv_loader.q, ingestion_log.q, db_writer.q, monitoring.q

\d .orchestrator

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

/ Source configuration table — populated by app config.q via addSources
source_config:([]
  source:`symbol$();
  app:`symbol$();
  required:`boolean$();
  directory:`symbol$();
  filePattern:();
  delimiter:`char$();
  frequency:`symbol$()
 );

/ App registry: app name -> refresh function
appRegistry:()!()

/ Archive path for processed CSVs
archivePath:`:/data/archive

/ Timer interval in ms (default 1 hour)
timerInterval:3600000

/ Run state
isRunning:0b
runCount:0

/ ============================================================================
/ SOURCE REGISTRATION (called by app config.q)
/ ============================================================================

/ Register source entries at runtime
/ Args: sourceList - list of dicts or table rows matching source_config schema
addSources:{[sourceList]
  `.orchestrator.source_config upsert sourceList;
 }

/ ============================================================================
/ APP REGISTRATION
/ ============================================================================

/ Register an app's data refresh function
/ Called by each app's config.q: .orchestrator.registerApp[`myapp; .myapp.refresh]
/ Args:
/   app: symbol - app name (must match app column in source_config)
/   refreshFn: function - signature: {[date; availableSources] ...}
registerApp:{[app; refreshFn]
  .orchestrator.appRegistry[app]:refreshFn;
 }

/ ============================================================================
/ FILE SCANNING
/ ============================================================================

/ Scan all source directories for files matching patterns
/ Returns: table of (source; date; filepath)
scanAllSources:{[]
  results:([] source:`symbol$(); date:`date$(); filepath:`symbol$());

  {[results; row]
    dir:row`directory;
    pattern:row`filePattern;
    src:row`source;

    files:@[key; dir; {[e] `symbol$()}];
    if[0 = count files; :results];

    matched:files where files like pattern;
    if[0 = count matched; :results];

    {[results; src; dir; fn]
      dt:extractDate[fn];
      if[not null dt;
        fp:` sv dir , fn;
        `results insert (src; dt; fp)];
      results
    }[; src; dir]/[results; matched]
  }/[results; 0!source_config]
 }

/ Extract date from filename
/ Supports: YYYYMMDD, YYYY-MM-DD, YYYY_MM_DD, YYYY.MM.DD
extractDate:{[filename]
  fn:string filename;

  / Try YYYYMMDD (8 consecutive digits)
  digits:fn where fn in "0123456789";
  if[8 <= count digits;
    candidate:8#digits;
    dt:@["D"$; candidate[0 1 2 3],".",candidate[4 5],".",candidate[6 7]; 0Nd];
    if[not null dt; :dt]];

  / Try YYYY-MM-DD or YYYY_MM_DD or YYYY.MM.DD
  seps:where fn in "-_.";
  if[2 > count seps; :0Nd];
  if[(4 = first seps) & (7 = seps 1);
    candidate:fn[0 1 2 3],".",fn[5 6],".",fn[8 9];
    dt:@["D"$; candidate; 0Nd];
    if[not null dt; :dt]];

  0Nd
 }

/ ============================================================================
/ WORK IDENTIFICATION
/ ============================================================================

/ Filter scanned files to only new or previously-failed work
identifyWork:{[scanned]
  select from scanned where not .ingestionLog.isProcessed'[source; date]
 }

/ Group new work by app and date
groupByApp:{[work]
  work:work lj `source xkey select source, app, required from source_config;
  select sources:source, filepaths:filepath, requiredSources:source where required
    by app, date from work
 }

/ Check if all required sources for an app/date are available
dependenciesMet:{[app; dt; currentSources]
  requiredAll:exec source from source_config where app=app, required;
  previouslyDone:.ingestionLog.completedSources[dt];
  available:distinct currentSources , previouslyDone;
  all requiredAll in available
 }

/ ============================================================================
/ MAIN ORCHESTRATION LOOP
/ ============================================================================

run:{[]
  if[isRunning; :()];
  `.orchestrator.isRunning set 1b;
  `.orchestrator.runCount set runCount + 1;

  tickStart:.z.p;

  / Phase 1: Scan for files
  scanned:@[scanAllSources; ::;
    {[e] show "Scan error: ",e; 0#([] source:`$(); date:`date$(); filepath:`$())}];

  / Phase 2: Identify new work
  work:identifyWork scanned;

  if[0 < count work;
    / Phase 3: Group by app and date
    grouped:groupByApp work;

    / Phase 4+5: Check dependencies and dispatch
    {[row]
      app:row`app;
      dt:row`date;
      srcs:row`sources;
      fps:row`filepaths;

      / Check dependencies
      if[dependenciesMet[app; dt; srcs];
        / Build source -> filepath dict for the app
        sourceMap:srcs!fps;

        / Dispatch to app's refresh function
        dispatchApp[app; dt; sourceMap]];
    } each 0!grouped;
  ];

  / Phase 6: Persist ingestion log
  .ingestionLog.persist[];

  / Phase 7: Archive processed CSVs
  archiveCompleted[tickStart];

  / Phase 8: Monitoring
  @[.monitoring.checkAll; ::; {[e] show "Monitoring error: ",e}];

  `.orchestrator.isRunning set 0b;
 }

/ ============================================================================
/ APP DISPATCH
/ ============================================================================

/ Call an app's registered refresh function
dispatchApp:{[app; dt; sourceMap]
  if[not app in key appRegistry;
    show "No refresh function registered for app: ",string app;
    :()];

  refreshFn:appRegistry app;

  / Mark all sources as processing
  {[src; dt; fp]
    .ingestionLog.markProcessing[src; dt; fp];
  }[; dt;]'[key sourceMap; value sourceMap];

  / Call the app's refresh function
  result:@[refreshFn; (dt; sourceMap);
    {[e] show "App refresh failed: ",e; `error}];

  if[`error ~ result;
    / Mark sources as failed
    {[src; dt]
      .ingestionLog.markFailed[src; dt; "App refresh failed"];
    }[; dt] each key sourceMap;
    :()];

  / Mark sources as completed
  {[src; dt]
    .ingestionLog.markCompleted[src; dt; 0];
  }[; dt] each key sourceMap;
 }

/ ============================================================================
/ CSV ARCHIVING
/ ============================================================================

/ Archive CSV files that were successfully processed during this tick
archiveCompleted:{[tickStart]
  completed:@[.ingestionLog.completedSince; tickStart;
    {[e] ([] filepath:`symbol$(); date:`date$())}];
  if[0 = count completed; :()];

  {[row]
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
  } each 0!completed;
 }

/ ============================================================================
/ TIMER CONTROL
/ ============================================================================

start:{[]
  .z.ts:{.orchestrator.run[]};
  system "t ",string timerInterval;
  show "Orchestrator started. Interval: ",string[timerInterval],"ms";
 }

stop:{[]
  system "t 0";
  show "Orchestrator stopped.";
 }

setInterval:{[ms]
  `.orchestrator.timerInterval set ms;
  if[0 < system "t"; system "t ",string ms];
 }

setArchivePath:{[path]
  `.orchestrator.archivePath set path;
 }

/ ============================================================================
/ MANUAL OPERATIONS
/ ============================================================================

manualRefresh:{[app; dt]
  allSources:exec source from source_config where app=app;
  fps:{[src; dt]
    dir:first exec directory from source_config where source=src;
    files:key dir;
    matched:files where files like first exec filePattern from source_config where source=src;
    dateMatched:matched where dt = extractDate each matched;
    if[0 = count dateMatched; :()];
    ` sv dir , first dateMatched
  }[; dt] each allSources;
  sourceMap:allSources!fps;
  sourceMap:sourceMap where not (::) ~/: value sourceMap;
  dispatchApp[app; dt; sourceMap];
 }

backfill:{[app; startDate; endDate]
  dates:startDate + til 1 + endDate - startDate;
  {[app; dt] manualRefresh[app; dt]}[app] each dates;
 }

status:{[]
  `isRunning`runCount`timerInterval`registeredApps`registeredSources`archivePath!(
    isRunning; runCount; timerInterval; key appRegistry; count source_config; archivePath)
 }

\d .
