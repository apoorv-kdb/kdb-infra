/ ingestion_log.q
/ Tracks all ingestion activity - what was loaded, when, status, record counts
/ Persisted to the partitioned database at the end of each orchestrator tick
/ Reloaded from the database on startup so state survives restarts
/ Dependencies: db_writer.q (for persistence)

/ ============================================================================
/ LOG TABLE
/ ============================================================================

.ingestionLog.init:{[]
  `.ingestionLog.tbl set ([]
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

.ingestionLog.reload:{[dbPath]
  @[{[dbPath]
    allDates:key dbPath;
    if[0 = count allDates; :.ingestionLog.init[]];
    system "l ",1 _ string dbPath;
    if[`infra_ingestion_log in tables[];
      `.ingestionLog.tbl set value `infra_ingestion_log];
    if[not `.ingestionLog.tbl in key `.; .ingestionLog.init[]];
  }; dbPath; {[e] .ingestionLog.init[]}];
 }

/ ============================================================================
/ PERSISTENCE
/ ============================================================================

.ingestionLog.persist:{[]
  if[0 = count .ingestionLog.tbl; :()];
  dates:distinct .ingestionLog.tbl`date;
  {[dt]
    subset:select from .ingestionLog.tbl where date = dt;
    .ingestionLog.persistPartition[dt; subset];
  } each dates;
 }

.ingestionLog.persistPartition:{[dt; data]
  dbPath:.dbWriter.dbPath;
  partPath:` sv (dbPath; `$string dt; `infra_ingestion_log; `);
  enumData:@[{[db; d] .Q.en[db; d]}[dbPath]; data; {[e] `ENUM_FAIL}];
  if[not `ENUM_FAIL ~ enumData;
    .[{[pp; d] pp set d}; (partPath; enumData); {[e] show "ingestion_log persist failed: ",e}]];
 }

/ ============================================================================
/ WRITE OPERATIONS
/ ============================================================================

.ingestionLog.markProcessing:{[src; dt; fp]
  existing:select from .ingestionLog.tbl where source = src, date = dt;
  if[count existing;
    update status:`processing, filepath:fp, startTime:.z.p, retryCount:1+first retryCount
      from `.ingestionLog.tbl where source = src, date = dt;
    :()];
  `.ingestionLog.tbl insert (src; dt; `processing; fp; 0j; ""; .z.p; 0Np; 0i);
 }

.ingestionLog.markCompleted:{[src; dt; recCount]
  update status:`completed, recordCount:recCount, endTime:.z.p
    from `.ingestionLog.tbl where source = src, date = dt;
 }

.ingestionLog.markFailed:{[src; dt; errMsg]
  update status:`failed, errorMsg:errMsg, endTime:.z.p
    from `.ingestionLog.tbl where source = src, date = dt;
 }

/ ============================================================================
/ READ OPERATIONS
/ ============================================================================

.ingestionLog.isProcessed:{[src; dt]
  0 < count select from .ingestionLog.tbl where source = src, date = dt, status = `completed
 }

.ingestionLog.completedSources:{[dt]
  exec source from .ingestionLog.tbl where date = dt, status = `completed
 }

.ingestionLog.getFailed:{[]
  select from .ingestionLog.tbl where status = `failed
 }

.ingestionLog.getByDate:{[dt]
  select from .ingestionLog.tbl where date = dt
 }

.ingestionLog.stats:{[]
  select count i by status from .ingestionLog.tbl
 }
