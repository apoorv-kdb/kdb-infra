/ db_writer.q
/ Save tables to the partitioned database with naming convention enforcement
/ If a schema is registered for a table name, validates data before saving
/ Gatekeeper: nothing enters the database without passing through here
/
/ Dependencies: validator.q

\d .dbWriter

/ ============================================================================
/ CONFIGURATION
/ ============================================================================

dbPath:`:curated_db
allowedDomains:`$()

addDomain:{[domain]
  if[not domain in .dbWriter.allowedDomains;
    `.dbWriter.allowedDomains set .dbWriter.allowedDomains , domain];
 }

setDbPath:{[path] `.dbWriter.dbPath set path}

/ ============================================================================
/ NAMING CONVENTION
/ ============================================================================

validateName:{[tableName]
  nm:string tableName;
  if[not "_" in nm; :`valid`error!(0b; "Table name must follow {domain}_{category}_{...} pattern")];
  domain:`$first "_" vs nm;
  if[not domain in allowedDomains;
    :`valid`error!(0b; "Unknown domain: ",string[domain],". Registered: ",", " sv string allowedDomains)];
  `valid`error!(1b; "")
 }

/ ============================================================================
/ PARTITIONED WRITES
/ ============================================================================

save:{[tableName; data; dt]
  nameCheck:validateName tableName;
  if[not nameCheck`valid; :`success`error`recordCount!(0b; nameCheck`error; 0)];

  if[not 98h = type data; :`success`error`recordCount!(0b; "Data must be a table"; 0)];
  if[0 = count data; :`success`error`recordCount!(0b; "Cannot save empty table"; 0)];

  / If a schema exists for this table, validate against it
  if[.validator.hasSchema[tableName];
    schema:.validator.getSchema[tableName];
    validation:.validator.validateSchema[data; schema];
    if[not validation`valid;
      :`success`error`recordCount!(0b; "Schema validation failed: ","; " sv validation`errors; 0)]];

  / Enumerate symbols
  enumData:@[{[db; d] .Q.en[db; d]}[dbPath]; data; {[e] `ENUM_FAIL}];
  if[`ENUM_FAIL ~ enumData;
    :`success`error`recordCount!(0b; "Symbol enumeration failed"; 0)];

  / Write to partition
  partPath:` sv dbPath , (`$string dt) , tableName , `;
  @[{[pp; d] pp set d}; (partPath; enumData);
    {[e] :`success`error`recordCount!(0b; "Write failed: ",e; 0)}];

  `success`error`recordCount!(1b; ""; count data)
 }

saveMultiple:{[tableMap; dt]
  {[tbl; data; dt] save[tbl; data; dt]}[; ; dt] ./: flip (key tableMap; value tableMap)
 }

saveFlat:{[tableName; data]
  nameCheck:validateName tableName;
  if[not nameCheck`valid; :`success`error!(0b; nameCheck`error)];

  enumData:@[{[db; d] .Q.en[db; d]}[dbPath]; data; {[e] `ENUM_FAIL}];
  if[`ENUM_FAIL ~ enumData; :`success`error!(0b; "Symbol enumeration failed")];

  tblPath:` sv dbPath , tableName;
  @[{[p; d] p set d}; (tblPath; enumData);
    {[e] :`success`error!(0b; "Write failed: ",e)}];

  `success`error!(1b; "")
 }

/ ============================================================================
/ DATABASE OPERATIONS
/ ============================================================================

reload:{[]
  @[{system "l ",1 _ string .dbWriter.dbPath}; ::; {[e] show "DB reload failed: ",e}];
 }

listPartitions:{[]
  dates:key dbPath;
  asc "D"$string dates where not null "D"$string dates
 }

listTables:{[dt]
  partPath:` sv dbPath , `$string dt;
  tbls:key partPath;
  tbls where not tbls in `sym`.d
 }

\d .
