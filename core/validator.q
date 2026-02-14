/ validator.q
/ Central schema registry and rule-based data quality validation
/ Schemas registered here are used by csv_loader (on load) and db_writer (on save)

\d .validator

/ ============================================================================
/ SCHEMA REGISTRY
/ ============================================================================

/ Central schema store: name (symbol) -> schema (dict)
schemas:()!()

/ Register a schema
/ Args:
/   name: symbol - source name or derived table name
/   schema: dict with keys:
/     `columns - symbol list of expected columns
/     `types - char list of kdb types aligned with columns
/     `mandatory - symbol list of columns that cannot be null
/     `rules - (optional) list of custom validation rule dicts
registerSchema:{[name; schema]
  .validator.schemas[name]:schema;
 }

/ Look up a schema (returns (::) if not found)
getSchema:{[name]
  $[name in key schemas; schemas name; (::)]
 }

/ Check if a schema exists for a given name
hasSchema:{[name]
  name in key schemas
 }

/ ============================================================================
/ VALIDATION RULES
/ ============================================================================

/ Validate not null
notNull:{[data; col]
  mask:null data col;
  `pass`failures!(not any mask; where mask)
 }

/ Validate type cast
typeCheck:{[data; col; expectedType]
  vals:data col;
  attempted:@[expectedType$; vals; {[e] `CAST_ERROR}];
  if[`CAST_ERROR ~ attempted; :`pass`failures!(0b; til count data)];
  inputNulls:null vals;
  outputNulls:null attempted;
  newNulls:outputNulls & not inputNulls;
  `pass`failures!(not any newNulls; where newNulls)
 }

/ Validate values in allowed set
inSet:{[data; col; allowed]
  mask:not data[col] in allowed;
  `pass`failures!(not any mask; where mask)
 }

/ Validate numeric range
inRange:{[data; col; minVal; maxVal]
  vals:"F"$string data col;
  mask:(vals < minVal) | vals > maxVal;
  `pass`failures!(not any mask; where mask)
 }

/ Validate uniqueness
unique:{[data; keyCols]
  subset:keyCols#data;
  dups:where 1 < count each group flip subset;
  `pass`failures!(0 = count dups; dups)
 }

/ Validate row count in range
rowCount:{[data; minRows; maxRows]
  n:count data;
  pass:(n >= minRows) & n <= maxRows;
  `pass`failures!(pass; $[pass; `long$(); enlist n])
 }

/ ============================================================================
/ SCHEMA VALIDATION
/ ============================================================================

/ Validate data against a full schema definition
validateSchema:{[data; schema]
  errors:();

  / Check required columns exist
  missing:schema[`columns] except cols data;
  if[count missing;
    errors,:enlist "Missing columns: ",", " sv string missing];

  / Check mandatory columns have no nulls
  if[`mandatory in key schema;
    {[data; col; errors]
      res:.validator.notNull[data; col];
      if[not res`pass;
        errors,:enlist "Null values in mandatory column: ",string[col],
          " (",string[count res`failures]," rows)"];
      errors
    }[data]/[errors; schema[`mandatory] inter cols data]];

  / Check types can be cast
  validCols:schema[`columns] inter cols data;
  typeMap:schema[`columns]!schema`types;
  {[data; col; typ; errors]
    res:.validator.typeCheck[data; col; typ];
    if[not res`pass;
      errors,:enlist "Type cast failure for column: ",string[col],
        " (expected ",string[typ],", ",string[count res`failures]," rows failed)"];
    errors
  }[data]/[errors; validCols; typeMap validCols];

  / Run custom rules if defined
  if[`rules in key schema;
    {[data; rule; errors]
      res:@[rule`fn; (data; rule`params); {[e] `pass`failures!(0b; enlist "Rule error: ",e)}];
      if[not res`pass;
        errors,:enlist rule[`name],": ",string[count res`failures]," failures"];
      errors
    }[data]/[errors; schema`rules]];

  `valid`errors!(0 = count errors; errors)
 }

\d .
