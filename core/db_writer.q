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

  if[.validator.hasSchema[tableName];
    schema:.validator.getSchema[tableName];
    validation:.validator.validateSchema[data; schema];
    if[not validation`valid;
      :`success`error`recordCount!(0b;
        "Schema validation failed: ","; " sv validation`errors; 0)]];

  writePartition[tableName; data; dt]
 }

saveMultiple:{[tableMap; dt]
  {[dt; tblName; data]
    .dbWriter.save[tblName; data; dt]
  }[dt]'[key tableMap; value tableMap]
 }

/ ============================================================================
/ NON-PARTITIONED WRITES
/ ============================================================================

saveFlat:{[tableName; data]
  nameCheck:validateName tableName;
  if[not nameCheck`valid; :`success`error`recordCount!(0b; nameCheck`error; 0)];
  if[not 98h = type data; :`success`error`recordCount!(0b; "Data must be a table"; 0)];

  flatPath:` sv dbPath , tableName , `;
  enumData:@[{[db; d] .Q.en[db; d]}[dbPath]; data; {[e] `ENUM_FAIL}];
  if[`ENUM_FAIL ~ enumData;
    :`success`error`recordCount!(0b; "Symbol enumeration failed"; 0)];

  writeResult:@[{[fp; d] fp set d; `ok}; (flatPath; enumData); {[e] e}];
  if[not `ok ~ writeResult;
    :`success`error`recordCount!(0b; "Write failed: ",writeResult; 0)];

  `success`error`recordCount!(1b; ""; count data)
 }

/ ============================================================================
/ INTERNAL
/ ============================================================================

writePartition:{[tableName; data; dt]
  partPath:` sv dbPath , `$string[dt] , tableName , `;

  enumData:@[{[db; d] .Q.en[db; d]}[dbPath]; data; {[e] `ENUM_FAIL}];
  if[`ENUM_FAIL ~ enumData;
    :`success`error`recordCount!(0b; "Symbol enumeration failed"; 0)];

  writeResult:@[{[pp; d] pp set d; `ok}; (partPath; enumData); {[e] e}];
  if[not `ok ~ writeResult;
    :`success`error`recordCount!(0b; "Write failed: ",writeResult; 0)];

  `success`error`recordCount!(1b; ""; count data)
 }

/ ============================================================================
/ DATABASE OPERATIONS
/ ============================================================================

reload:{[]
  @[{system "l ",1 _ string .dbWriter.dbPath; `ok}; ::; {[e] `FAIL}]
 }

listPartitions:{[] key dbPath}

listTables:{[dt] key ` sv dbPath , `$string dt}

setDbPath:{[path] `.dbWriter.dbPath set path}

\d .
