/ core/db_writer.q
/ Write tables to the partitioned database with naming convention enforcement.
/ Dependencies: none

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

.dbWriter.dbPath:`:C:/data/databases/prod_parallel
.dbWriter.allowedDomains:`$()

.dbWriter.addDomain:{[dom]
  if[not dom in .dbWriter.allowedDomains;
    `.dbWriter.allowedDomains set .dbWriter.allowedDomains , dom];
 }

.dbWriter.setDbPath:{[path] `.dbWriter.dbPath set path}

/ ============================================================================
/ NAMING CONVENTION
/ ============================================================================

.dbWriter.validateName:{[tblName]
  nm:string tblName;
  if[not "_" in nm; :`valid`error!(0b; "Table name must follow {domain}_{name} pattern")];
  dom:`$first "_" vs nm;
  if[not dom in .dbWriter.allowedDomains;
    :`valid`error!(0b; "Unknown domain: ",string[dom],". Registered: ",", " sv string .dbWriter.allowedDomains)];
  `valid`error!(1b; "")
 }

/ ============================================================================
/ PARTITIONED WRITES
/ ============================================================================

.dbWriter.writePartition:{[tblName; tbl; dt]
  nameCheck:.dbWriter.validateName tblName;
  if[not nameCheck`valid; 'nameCheck`error];
  if[not 98h = type tbl; '"Data must be a table"];
  if[0 = count tbl; '"Cannot save empty table"];

  enumData:@[{[db; d] .Q.en[db; d]}[.dbWriter.dbPath]; tbl; {[e] '"Enum failed: ",e}];

  partPath:` sv (.dbWriter.dbPath; `$string dt; tblName; `);
  .[{[pp; d] pp set d}; (partPath; enumData); {[e] '"Write failed: ",e}];

  show "  Saved ",string[tblName]," for ",string[dt],": ",string[count tbl]," rows";
  count tbl
 }

.dbWriter.writeMultiple:{[tableMap; dt]
  {[dt; tblName; tbl] .dbWriter.writePartition[tblName; tbl; dt]}[dt] ./: flip (key tableMap; value tableMap)
 }

/ ============================================================================
/ DATABASE OPERATIONS
/ ============================================================================

.dbWriter.reload:{[]
  @[{system "l ",1 _ string .dbWriter.dbPath}; ::; {[e] show "DB reload failed: ",e}];
 }

.dbWriter.listPartitions:{[]
  dates:key .dbWriter.dbPath;
  asc "D"$string dates where not null "D"$string dates
 }

.dbWriter.listTables:{[dt]
  partPath:` sv (.dbWriter.dbPath; `$string dt);
  tbls:key partPath;
  tbls where not tbls in `sym`.d
 }

show "  db_writer.q loaded"
