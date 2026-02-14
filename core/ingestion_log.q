/ ingestion_log.q
/ Tracks all ingestion activity - what was loaded, when, status, record counts
/ Persisted to the partitioned database at the end of each orchestrator tick
/ Reloaded from the database on startup so state survives restarts
/
/ Dependencies: db_writer.q (for persistence)

\d .ingestionLog

/ ============================================================================
/ LOG TABLE
/ ============================================================================

persistTableName:`infra_ingestion_log

init:{[]
  `ingestion_log set ([]
    source:`symbol$();
    date:`date$();
    status:`symbol$();
    filepath:`symbol$();
    recordCount:`long$();
    errorMsg:();
    startTime:`timestamp$();
    endTime:`timestamp$();
    retryCount:`int$()
  );
 }

reload:{[dbPath]
  allDates:@[key; dbPath; {[e] `date$()}];
  if[0 = count allDates; :init[]];

  loaded:@[
    {[dbPath; tblName]
      system "l ",1 _ string dbPath;
      if[tblName in tables[];
        `ingestion_log set value tblName;
        :1b];
      :0b
    };
    (dbPath; persistTableName);
    {[e] 0b}];

  if[not loaded; init[]];
 }

/ ============================================================================
/ PERSISTENCE
/ ============================================================================

persist:{[]
  if[0 = count ingestion_log; :()];
  dates:distinct ingestion_log`date;
  {[dt]
    subset:select from ingestion_log where date=dt;
    .ingestionLog.writePartition[dt; subset];
  } each dates;
 }

writePartition:{[dt; data]
  dbPath:.dbWriter.dbPath;
  partPath:` sv dbPath , `$string[dt] , persistTableName , `;
  enumData:@[{[db; d] .Q.en[db; d]}[dbPath]; data; {[e] `ENUM_FAIL}];
  if[not `ENUM_FAIL ~ enumData;
    @[{[pp; d] pp set d}; (partPath; enumData); {[e] show "ingestion_log persist failed: ",e}]];
 }

/ ============================================================================
/ WRITE OPERATIONS
/ ============================================================================

markProcessing:{[source; dt; fp]
  existing:select from ingestion_log where source=source, date=dt;
  if[count existing;
    ![`ingestion_log;
      enlist (=;`source;enlist source) , enlist (=;`date;enlist dt);
      0b;
      `status`filepath`startTime`retryCount!
        (`processing; fp; .z.p; first[existing`retryCount]+1i)];
    :()];
  `ingestion_log insert (source; dt; `processing; fp; 0; ""; .z.p; 0Np; 0i);
 }

markCompleted:{[source; dt; recCount]
  ![`ingestion_log;
    enlist (=;`source;enlist source) , enlist (=;`date;enlist dt);
    0b;
    `status`recordCount`endTime`errorMsg!(`completed; recCount; .z.p; "")];
 }

markFailed:{[source; dt; errMsg]
  ![`ingestion_log;
    enlist (=;`source;enlist source) , enlist (=;`date;enlist dt);
    0b;
    `status`endTime`errorMsg!(`failed; .z.p; errMsg)];
 }

/ ============================================================================
/ QUERY OPERATIONS
/ ============================================================================

isProcessed:{[source; dt]
  0 < count select from ingestion_log where source=source, date=dt, status=`completed
 }

getStatus:{[source; dt]
  select from ingestion_log where source=source, date=dt
 }

getBySource:{[source]
  select from ingestion_log where source=source
 }

getFailed:{[]
  select from ingestion_log where status=`failed
 }

getByDate:{[dt]
  select from ingestion_log where date=dt
 }

getLatest:{[]
  select last status, last date, last recordCount, last endTime, last errorMsg
    by source from ingestion_log
 }

allCompleted:{[sources; dt]
  completed:exec source from ingestion_log where date=dt, status=`completed;
  all sources in completed
 }

completedSources:{[dt]
  exec source from ingestion_log where date=dt, status=`completed
 }

completedSince:{[ts]
  select source, date, filepath from ingestion_log
    where status=`completed, endTime >= ts
 }

/ ============================================================================
/ MAINTENANCE
/ ============================================================================

purgeOld:{[days]
  cutoff:.z.d - days;
  delete from `ingestion_log where date < cutoff;
 }

stats:{[]
  select records:count i,
    completed:sum status=`completed,
    failed:sum status=`failed,
    processing:sum status=`processing
    by source from ingestion_log
 }

\d .
