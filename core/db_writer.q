/ db_writer.q
/ Write tables to the partitioned database with naming convention enforcement
/ If a schema is registered for a table name, validates data before saving
/ Gatekeeper: nothing enters the database without passing through here
/ Dependencies: validator.q

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

.dbWriter.dbPath:`:curated_db
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
  if[not "_" in nm; :`valid`error!(0b; "Table name must follow {domain}_{category}_{...} pattern")];
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

  if[.validator.hasSchema[tblName];
    schema:.validator.getSchema[tblName];
    validation:.validator.validateSchema[tbl; schema];
    if[not validation`valid;
      '"Schema validation failed: ","; " sv validation`errors]];

  enumData:@[{[db; d] .Q.en[db; d]}[.dbWriter.dbPath]; tbl; {[e] '"Enum failed: ",e}];

  partPath:` sv (.dbWriter.dbPath; `$string dt; tblName; `);
  .[{[pp; d] pp set d}; (partPath; enumData); {[e] '"Write failed: ",e}];

  show "  Saved ",string[tblName]," for ",string[dt],": ",string[count tbl]," rows";
  count tbl
 }

.dbWriter.writeMultiple:{[tableMap; dt]
  {[dt; tblName; tbl] .dbWriter.writePartition[tblName; tbl; dt]}[dt] ./: flip (key tableMap; value tableMap)
 }

.dbWriter.writeFlat:{[tblName; tbl]
  nameCheck:.dbWriter.validateName tblName;
  if[not nameCheck`valid; 'nameCheck`error];

  enumData:@[{[db; d] .Q.en[db; d]}[.dbWriter.dbPath]; tbl; {[e] '"Enum failed: ",e}];

  tblPath:` sv (.dbWriter.dbPath; tblName);
  .[{[p; d] p set d}; (tblPath; enumData); {[e] '"Write failed: ",e}];
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
