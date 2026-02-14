/ orchestrator.q
/ Main orchestration loop - scans for files, checks dependencies, dispatches app data refreshes
/ At end of each tick: persists ingestion_log, archives processed CSVs, runs monitoring
/
/ Dependencies: csv_loader.q, validator.q, ingestion_log.q, db_writer.q, monitoring.q, sources.q

\d .orchestrator

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

timerInterval:3600000
archivePath:`:/data/archive
appRegistry:()!()
isRunning:0b
runCount:0

/ ============================================================================
/ APP REGISTRATION
/ ============================================================================

registerApp:{[app; refreshFn]
  .orchestrator.appRegistry[app]:refreshFn;
 }

/ ============================================================================
/ FILE SCANNING
/ ============================================================================

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

extractDate:{[filename]
  fn:string filename;

  digits:fn where fn in "0123456789";
  if[8 <= count digits;
    candidate:8#digits;
    dt:@["D"$; candidate[0 1 2 3],".",candidate[4 5],".",candidate[6 7]; 0Nd];
    if[not null dt; :dt]];

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

identifyWork:{[scanned]
  select from scanned where not .ingestionLog.isProcessed'[source; date]
 }

groupByApp:{[work]
  work:work lj `source xkey select source, app, required from source_config;
  select sources:source, filepaths:filepath, requiredSources:source where required
    by app, date from work
 }

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
    / Phase 3: Group by app
    grouped:groupByApp work;

    / Phase 4: Process each app/date
    {[row; work]
      app:row`app;
      dt:row`date;
      sources:row`sources;

      if[dependenciesMet[app; dt; sources];
        allAvailable:exec source from source_config
          where app=app, source in (sources , .ingestionLog.completedSources[dt]);

        {[src; dt; work]
          fp:first exec filepath from work where source=src, date=dt;
          .ingestionLog.markProcessing[src; dt; fp];
        }[; dt; work] each sources;

        dispatchApp[app; dt; allAvailable]
      ];
    }[; work] each 0!grouped;
  ];

  / Phase 5: Persist ingestion log to database
  @[.ingestionLog.persist; ::; {[e] show "ingestion_log persist error: ",e}];

  / Phase 6: Archive processed CSVs
  @[archiveCompleted; tickStart; {[e] show "Archive error: ",e}];

  / Phase 7: Monitoring
  @[.monitoring.runChecks; ::; {[e] show "Monitoring error: ",e}];

  `.orchestrator.isRunning set 0b;
 }

dispatchApp:{[app; dt; availableSources]
  if[not app in key appRegistry;
    show "No registered refresh function for app: ",string app;
    :()];

  refreshFn:appRegistry app;
  result:@[refreshFn; (dt; availableSources); {[e] `error!e}];

  if[99h = type result;
    if[`error in key result;
      {[src; dt; errMsg]
        .ingestionLog.markFailed[src; dt; errMsg];
      }[; dt; result`error] each exec source from source_config where app=app;
      show "App ",string[app]," failed for ",string[dt],": ",result`error;
      :()]];

  {[src; dt]
    .ingestionLog.markCompleted[src; dt; 0];
  }[; dt] each exec source from source_config where app=app;
 }

/ ============================================================================
/ CSV ARCHIVING
/ ============================================================================

archiveCompleted:{[tickStart]
  completed:.ingestionLog.completedSince[tickStart];
  if[0 = count completed; :()];

  {[row]
    fp:row`filepath;
    dt:row`date;

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
  dispatchApp[app; dt; allSources];
 }

backfill:{[app; startDate; endDate]
  dates:startDate + til 1 + endDate - startDate;
  {[app; dt] manualRefresh[app; dt]}[app] each dates;
 }

status:{[]
  `isRunning`runCount`timerInterval`registeredApps`archivePath!(
    isRunning; runCount; timerInterval; key appRegistry; archivePath)
 }

\d .
