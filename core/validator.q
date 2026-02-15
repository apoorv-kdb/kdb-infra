/ validator.q
/ Central schema registry and validation rule library
/ Schemas registered here are used by csv_loader (on load) and db_writer (on save)

\d .validator

/ ============================================================================
/ SCHEMA REGISTRY
/ ============================================================================

/ Schema storage: name -> schema dict
schemas:()!()

/ Register a schema
/ Args:
/   name: symbol - source or derived table name
/   schema: dict with keys `columns`types`mandatory (and optional `rules)
registerSchema:{[name; schema]
  .validator.schemas[name]:schema;
 }

/ Get a schema (returns (::) if not found)
getSchema:{[name]
  $[name in key schemas; schemas name; (::)]
 }

/ Check if a schema exists
hasSchema:{[name] name in key schemas}

/ ============================================================================
/ VALIDATION RULES
/ ============================================================================

/ Check for nulls in a column
/ Returns: dict `valid`message
notNull:{[data; col]
  nullCount:sum null data col;
  $[0 = nullCount;
    `valid`message!(1b; "");
    `valid`message!(0b; string[col]," has ",string[nullCount]," nulls")]
 }

/ Check column can be cast to a type
typeCheck:{[data; col; typ]
  result:@[{[t; v] t$v; 1b}[typ]; data col; {[e] 0b}];
  $[result;
    `valid`message!(1b; "");
    `valid`message!(0b; string[col]," cannot be cast to type ",string typ)]
 }

/ Check values are in an allowed set
inSet:{[data; col; allowed]
  bad:data col where not data[col] in allowed;
  $[0 = count bad;
    `valid`message!(1b; "");
    `valid`message!(0b; string[col]," has invalid values: ",", " sv string distinct bad)]
 }

/ Check numeric range
inRange:{[data; col; minVal; maxVal]
  vals:data col;
  bad:vals where (vals < minVal) | vals > maxVal;
  $[0 = count bad;
    `valid`message!(1b; "");
    `valid`message!(0b; string[col]," has ",string[count bad]," values outside [",string[minVal],",",string[maxVal],"]")]
 }

/ Check uniqueness of key columns
unique:{[data; keyCols]
  grouped:?[data; (); keyCols!keyCols; (enlist `cnt)!enlist (count; `i)];
  dupes:select from grouped where cnt > 1;
  $[0 = count dupes;
    `valid`message!(1b; "");
    `valid`message!(0b; string[count dupes]," duplicate keys found on ",", " sv string keyCols)]
 }

/ Check row count is within expected range
rowCount:{[data; minRows; maxRows]
  n:count data;
  $[(n >= minRows) & n <= maxRows;
    `valid`message!(1b; "");
    `valid`message!(0b; "Row count ",string[n]," outside expected [",string[minRows],",",string[maxRows],"]")]
 }

/ ============================================================================
/ SCHEMA VALIDATION
/ ============================================================================

/ Validate data against a registered schema
/ Checks: columns present, mandatory not null, types castable
/ Args: data (table), schema (dict)
/ Returns: dict `valid`errors
validateSchema:{[data; schema]
  errors:();

  / Check required columns exist
  missing:schema[`columns] where not schema[`columns] in cols data;
  if[count missing;
    errors,:enlist "Missing columns: ",", " sv string missing];

  / Check mandatory columns for nulls
  mandatoryCols:schema`mandatory;
  mandatoryCols:mandatoryCols where mandatoryCols in cols data;
  {[data; col; errors]
    res:notNull[data; col];
    if[not res`valid; errors,:enlist res`message];
    errors
  }[data]/[errors; mandatoryCols];

  / Check types
  types:schema`types;
  typeCols:schema[`columns] where schema[`columns] in cols data;
  typeMap:typeCols!(count typeCols)#types;
  {[data; col; typ; errors]
    res:typeCheck[data; col; typ];
    if[not res`valid; errors,:enlist res`message];
    errors
  }[data]/[errors; key typeMap; value typeMap];

  / Run custom rules if present
  if[`rules in key schema;
    {[data; rule; errors]
      res:@[(rule`fn); (data; rule`params); {[e] `valid`message!(0b; "Rule failed: ",e)}];
      if[not res`valid; errors,:enlist res`message];
      errors
    }[data]/[errors; schema`rules]];

  `valid`errors!((0 = count errors); errors)
 }

\d .
