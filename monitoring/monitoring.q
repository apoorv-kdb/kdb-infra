/ monitoring.q
/ Health monitoring - checks ingestion_log for failures and staleness, triggers alerts
/ Called at the end of each orchestrator tick
/
/ Dependencies: ingestion_log.q

\d .monitoring

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

stalenessThresholdHours:36

alertFn:{[severity; subject; body]
  show string[.z.p]," [",string[severity],"] ",subject;
  show body;
 }

setAlertFn:{[fn] `.monitoring.alertFn set fn}

minDiskSpaceGB:50

/ ============================================================================
/ CHECKS
/ ============================================================================

checkAll:{[]
  checkFailures[];
  checkStaleness[];
  checkDiskSpace[];
 }

checkFailures:{[]
  failures:.ingestionLog.getFailed[];
  todayFailures:select from failures where date >= .z.d;
  if[0 = count todayFailures; :()];

  msg:"Failed ingestions today:\n";
  msg,:{[row]
    "  ",string[row`source]," (",string[row`date],"): ",row`errorMsg,"\n"
  } each 0!todayFailures;

  alertFn[`CRITICAL; "Ingestion Failures Detected"; msg];
 }

checkStaleness:{[]
  dailySources:select source, app from .orchestrator.source_config where frequency=`daily;
  if[0 = count dailySources; :()];

  cutoff:.z.p - `long$stalenessThresholdHours * 3600000000000;

  stale:();
  {[cutoff; src; stale]
    history:select from ingestion_log where source=src, status=`completed;
    if[0 = count history;
      stale,:enlist src;
      :stale];
    lastComplete:exec max endTime from history;
    if[lastComplete < cutoff;
      stale,:enlist src];
    stale
  }[cutoff]/[stale; exec source from dailySources];

  if[0 = count stale; :()];

  msg:"Sources not updated within ",string[stalenessThresholdHours]," hours:\n";
  msg,:"  ",", " sv string stale;

  alertFn[`WARN; "Stale Sources Detected"; msg];
 }

checkDiskSpace:{[]
  diskInfo:@[{system "df -BG ",1 _ string .dbWriter.dbPath}; ::; {[e] ()}];
  if[0 = count diskInfo; :()];
  if[1 >= count diskInfo; :()];

  parts:" " vs diskInfo 1;
  parts:parts where count each parts;
  if[4 > count parts; :()];

  availStr:parts 3;
  availGB:@["J"$; availStr except "G"; 0];

  if[availGB < minDiskSpaceGB;
    alertFn[`CRITICAL;
      "Low Disk Space";
      "Available: ",availStr,". Threshold: ",string[minDiskSpaceGB],"G"]];
 }

/ ============================================================================
/ REPORTING
/ ============================================================================

healthReport:{[]
  stats:.ingestionLog.stats[];
  orchStatus:.orchestrator.status[];
  recentFails:select from ingestion_log where status=`failed, date >= .z.d - 7;
  `ingestionStats`orchestratorStatus`recentFailures!(stats; orchStatus; recentFails)
 }

dailyReport:{[dt]
  entries:.ingestionLog.getByDate[dt];
  completed:select from entries where status=`completed;
  failed:select from entries where status=`failed;
  pending:exec source from .orchestrator.source_config where
    not source in (exec source from entries where status=`completed);
  `date`completed`failed`pendingSources!(dt; completed; failed; pending)
 }

\d .
