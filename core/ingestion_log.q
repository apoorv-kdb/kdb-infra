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
    update status:`processing, filepath:fp, startTime:.z.p, retryCount:1+first retryCount
      from `ingestion_log where source=source, date=dt;
    :()];
  `ingestion_log insert (source; dt; `processing; fp; 0j; ""; .z.p; 0Np; 0i);
 }

markCompleted:{[source; dt; recCount]
  update status:`completed, recordCount:recCount, endTime:.z.p
    from `ingestion_log where source=source, date=dt;
 }

markFailed:{[source; dt; errMsg]
  update status:`failed, errorMsg:errMsg, endTime:.z.p
    from `ingestion_log where source=source, date=dt;
 }

/ ============================================================================
/ READ OPERATIONS
/ ============================================================================

isProcessed:{[source; dt]
  0 < count select from ingestion_log where source=source, date=dt, status=`completed
 }

completedSources:{[dt]
  exec source from ingestion_log where date=dt, status=`completed
 }

allCompleted:{[sources; dt]
  done:completedSources[dt];
  all sources in done
 }

completedSince:{[ts]
  select from ingestion_log where status=`completed, endTime >= ts
 }

getFailed:{[]
  select from ingestion_log where status=`failed
 }

getByDate:{[dt]
  select from ingestion_log where date=dt
 }

stats:{[]
  select count i by status from ingestion_log
 }

\d .
