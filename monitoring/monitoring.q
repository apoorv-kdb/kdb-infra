/ monitoring.q
/ Health monitoring - checks ingestion_log for failures and staleness
/ Called at the end of each orchestrator tick
/ Dependencies: ingestion_log.q

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

.monitoring.stalenessThresholdHours:36

.monitoring.alertFn:{[severity; subject; body]
  show string[.z.p]," [",string[severity],"] ",subject;
  show body;
 }

.monitoring.setAlertFn:{[fn] `.monitoring.alertFn set fn}

/ ============================================================================
/ CHECKS
/ ============================================================================

.monitoring.checkAll:{[]
  .monitoring.checkFailures[];
  .monitoring.checkStaleness[];
 }

.monitoring.checkFailures:{[]
  failures:.ingestionLog.getFailed[];
  todayFailures:select from failures where date >= .z.d;
  if[0 = count todayFailures; :()];

  msg:"Failed ingestions today:\n";
  msg,:{[idx]
    row:todayFailures idx;
    "  ",string[row`source]," (",string[row`date],"): ",row`errorMsg,"\n"
  } each til count todayFailures;

  .monitoring.alertFn[`CRITICAL; "Ingestion Failures Detected"; msg];
 }

.monitoring.checkStaleness:{[]
  dailySources:select source, app from .orchestrator.source_config where frequency = `daily;
  if[0 = count dailySources; :()];

  cutoff:.z.p - `long$.monitoring.stalenessThresholdHours * 3600000000000;

  stale:{[cutoff; stale; src]
    history:select from .ingestionLog.tbl where source = src, status = `completed;
    if[0 = count history; :stale , enlist src];
    lastComplete:exec max endTime from history;
    if[lastComplete < cutoff; :stale , enlist src];
    stale
  }[cutoff]/[(); exec source from dailySources];

  if[0 = count stale; :()];

  msg:"Sources not updated within ",string[.monitoring.stalenessThresholdHours]," hours:\n";
  msg,:"  ",", " sv string stale;

  .monitoring.alertFn[`WARN; "Stale Sources Detected"; msg];
 }

/ ============================================================================
/ REPORTING
/ ============================================================================

.monitoring.healthReport:{[]
  ingStats:.ingestionLog.stats[];
  orchStatus:.orchestrator.status[];
  recentFails:select from .ingestionLog.tbl where status = `failed, date >= .z.d - 7;
  `ingestionStats`orchestratorStatus`recentFailures!(ingStats; orchStatus; recentFails)
 }

.monitoring.dailyReport:{[dt]
  entries:.ingestionLog.getByDate[dt];
  completed:select from entries where status = `completed;
  failed:select from entries where status = `failed;
  pending:exec source from .orchestrator.source_config where
    not source in (exec source from entries where status = `completed);
  `date`completed`failed`pendingSources!(dt; completed; failed; pending)
 }
