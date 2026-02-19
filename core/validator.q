/ validator.q
/ Central schema registry and validation rule library
/ Schemas registered here are used by csv_loader (on ingest) and db_writer (on write)

/ ============================================================================
/ SCHEMA REGISTRY
/ ============================================================================

.validator.schemas:()!()

.validator.registerSchema:{[nm; schema]
  .validator.schemas[nm]:schema;
 }

.validator.getSchema:{[nm]
  $[nm in key .validator.schemas; .validator.schemas nm; (::)]
 }

.validator.hasSchema:{[nm] nm in key .validator.schemas}

/ ============================================================================
/ VALIDATION RULES
/ ============================================================================

.validator.notNull:{[tbl; col]
  nullCount:sum null tbl col;
  $[0 = nullCount;
    `valid`message!(1b; "");
    `valid`message!(0b; string[col]," has ",string[nullCount]," nulls")]
 }

/ typ is uppercase e.g. "D","S","J" - lowercase before casting
.validator.typeCheck:{[tbl; col; typ]
  t:lower typ;
  result:@[{[t; v] t$v; 1b}[t]; tbl col; {[e] 0b}];
  $[result;
    `valid`message!(1b; "");
    `valid`message!(0b; string[col]," cannot be cast to type ",string typ)]
 }

.validator.inSet:{[tbl; col; allowed]
  bad:tbl col where not tbl[col] in allowed;
  $[0 = count bad;
    `valid`message!(1b; "");
    `valid`message!(0b; string[col]," has invalid values: ",", " sv string distinct bad)]
 }

.validator.inRange:{[tbl; col; minVal; maxVal]
  vals:tbl col;
  bad:vals where (vals < minVal) | vals > maxVal;
  $[0 = count bad;
    `valid`message!(1b; "");
    `valid`message!(0b; string[col]," has ",string[count bad]," values outside [",string[minVal],",",string[maxVal],"]")]
 }

.validator.unique:{[tbl; keyCols]
  grouped:?[tbl; (); keyCols!keyCols; (enlist `cnt)!enlist (count; `i)];
  dupes:select from grouped where cnt > 1;
  $[0 = count dupes;
    `valid`message!(1b; "");
    `valid`message!(0b; string[count dupes]," duplicate keys found on ",", " sv string keyCols)]
 }

.validator.rowCount:{[tbl; minRows; maxRows]
  n:count tbl;
  $[(n >= minRows) & n <= maxRows;
    `valid`message!(1b; "");
    `valid`message!(0b; "Row count ",string[n]," outside expected [",string[minRows],",",string[maxRows],"]")]
 }

/ ============================================================================
/ SCHEMA VALIDATION
/ ============================================================================

.validator.validateSchema:{[tbl; schema]
  errors:();

  / Check required columns exist
  missing:schema[`columns] where not schema[`columns] in cols tbl;
  if[count missing;
    errors,:enlist "Missing columns: ",", " sv string missing];

  / Check mandatory columns for nulls
  mandatoryCols:schema`mandatory;
  mandatoryCols:mandatoryCols where mandatoryCols in cols tbl;
  errors:{[tbl; errors; col]
    res:.validator.notNull[tbl; col];
    if[not res`valid; :errors , enlist res`message];
    errors
  }[tbl]/[errors; mandatoryCols];

  / Check types
  types:schema`types;
  typeCols:schema[`columns] where schema[`columns] in cols tbl;
  typeMap:typeCols!(count typeCols)#types;
  errors:{[tbl; typeMap; errors; col]
    typ:typeMap col;
    res:.validator.typeCheck[tbl; col; typ];
    if[not res`valid; :errors , enlist res`message];
    errors
  }[tbl; typeMap]/[errors; key typeMap];

  / Run custom rules if present
  if[`rules in key schema;
    errors:{[tbl; errors; rule]
      res:@[(rule`fn); (tbl; rule`params); {[e] `valid`message!(0b; "Rule failed: ",e)}];
      if[not res`valid; :errors , enlist res`message];
      errors
    }[tbl]/[errors; schema`rules]];

  `valid`errors!((0 = count errors); errors)
 }
