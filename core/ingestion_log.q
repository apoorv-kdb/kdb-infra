/ core/ingestion_log.q
/ Tracks all ingestion activity - refreshUnit, date, status, table counts.
/ Persisted to partitioned DB at end of each orchestrator tick.
/ Reloaded from DB on startup so state survives restarts.
/ Dependencies: db_writer.q
//
/ Log shape:
/   refreshUnit | date | status | tableCounts | warnings | startTime | endTime
/   transactions | ...  | ...   | sales_transactions:1000,sales_by_region:950 | "" | ... | ...
//
/ tableCounts is serialised as a string: "tbl1:N,tbl2:M"

/ ============================================================================
/ LOG TABLE
/ ============================================================================

.ingestionLog.init:{[]
  `.ingestionLog.tbl set ([]
    refreshUnit:`symbol$();
    date:`date$();
    status:`symbol$();
    tableCounts:();
    warnings:();
    startTime:`timestamp$();
    endTime:`timestamp$()
  );
 }

.ingestionLog.reload:{[dbPath]
  @[{[dbPath]
    allDates:key dbPath;
    if[0=count allDates; :.ingestionLog.init[]];
    system "l ",1_string dbPath;
    if[`infra_ingestion_log in tables[];
      `.ingestionLog.tbl set value `infra_ingestion_log];
    if[not `.ingestionLog.tbl in key `.; .ingestionLog.init[]];
  }; dbPath; {[e] .ingestionLog.init[]}];
 }

.ingestionLog.load:.ingestionLog.reload;

/ ============================================================================
/ SERIALISATION HELPERS
/ ============================================================================

/ Serialise a tableCounts dict to string: "sales_transactions:1000,sales_by_region:950"
.ingestionLog.serialiseCounts:{[d]
  if[(0=count d) or 99h<>type d; :""];
  ", " sv {(string x),":",string y}'[key d; value d]
 }

/ ============================================================================
/ PERSISTENCE
/ ============================================================================

.ingestionLog.persist:{[]
  if[0=count .ingestionLog.tbl; :()];
  dates:distinct .ingestionLog.tbl`date;
  {[dt]
    subset:select from .ingestionLog.tbl where date=dt;
    .ingestionLog.persistPartition[dt; subset];
  } each dates;
 }

.ingestionLog.persistPartition:{[dt; data]
  dbPath:.dbWriter.dbPath;
  partPath:` sv (dbPath; `$string dt; `infra_ingestion_log; `);
  enumData:@[{[db; d] .Q.en[db; d]}[dbPath]; data; {[e] `ENUM_FAIL}];
  if[not `ENUM_FAIL~enumData;
    .[{[pp; d] pp set d}; (partPath; enumData); {[e] show "ingestion_log persist failed: ",e}]];
 }

/ ============================================================================
/ WRITE OPERATIONS
/ ============================================================================

.ingestionLog.markProcessing:{[ru; dt]
  existing:select from .ingestionLog.tbl where refreshUnit=ru, date=dt;
  if[count existing;
    update status:`processing, startTime:.z.p
      from `.ingestionLog.tbl where refreshUnit=ru, date=dt;
    :()];
  `.ingestionLog.tbl insert (ru; dt; `processing; enlist ""; enlist ""; .z.p; 0Np);
 }

/ tblCounts - dict of tableName(symbol) -> rowCount(long), e.g. `sales_transactions`sales_by_region!1000 950
/ warnings  - string or list of strings; pass "" or () for none
.ingestionLog.markCompleted:{[ru; dt; tblCounts; warnings]
  tcStr:.ingestionLog.serialiseCounts[tblCounts];
  warnStr:$[(::)~warnings; ""; 0=count warnings; "";
             10h=abs type warnings; warnings;
             "; " sv warnings];
  update status:`completed,
         tableCounts:enlist tcStr,
         warnings:enlist warnStr,
         endTime:.z.p
    from `.ingestionLog.tbl where refreshUnit=ru, date=dt;
 }

.ingestionLog.markFailed:{[ru; dt; errMsg]
  msg:$[10h=abs type errMsg; errMsg; "unknown error"];
  update status:`failed,
         warnings:enlist msg,
         endTime:.z.p
    from `.ingestionLog.tbl where refreshUnit=ru, date=dt;
 }

/ ============================================================================
/ READ OPERATIONS
/ ============================================================================

.ingestionLog.isProcessed:{[ru; dt]
  0<count select from .ingestionLog.tbl where refreshUnit=ru, date=dt, status=`completed
 }

.ingestionLog.completedRefreshUnits:{[dt]
  exec refreshUnit from .ingestionLog.tbl where date=dt, status=`completed
 }

.ingestionLog.getFailed:{[]
  select from .ingestionLog.tbl where status=`failed
 }

.ingestionLog.getByDate:{[dt]
  select from .ingestionLog.tbl where date=dt
 }

.ingestionLog.stats:{[]
  select count i by status from .ingestionLog.tbl
 }

show "  ingestion_log.q loaded"
