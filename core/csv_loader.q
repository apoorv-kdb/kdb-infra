/ csv_loader.q
/ Load CSV files, validate against schema, type cast to proper types
/ Returns clean, typed tables ready for use by applications
/
/ Dependencies: validator.q

\d .csv

/ ============================================================================
/ LOAD AND CAST
/ ============================================================================

load:{[source; filepath; delimiter]
  if[(::) ~ delimiter; delimiter:","];

  schema:.validator.getSchema[source];
  if[(::) ~ schema;
    :`success`data`error`recordCount!(0b; (); "Unknown source: ",string source; 0)];

  raw:@[{[fp; delim] (delim; enlist delim) 0: fp}; (hsym `$string filepath; delimiter);
    {[e] `ERR}];
  if[`ERR ~ raw;
    :`success`data`error`recordCount!(0b; (); "Failed to read file"; 0)];
  if[0 = count raw;
    :`success`data`error`recordCount!(0b; (); "File is empty"; 0)];

  if[`mandatory in key schema;
    missingMandatory:schema[`mandatory] except cols raw;
    if[count missingMandatory;
      :`success`data`error`recordCount!(0b; ();
        "Missing mandatory columns: ",", " sv string missingMandatory; 0)]];

  keepCols:schema[`columns] inter cols raw;
  filtered:keepCols # raw;

  validation:.validator.validateSchema[filtered; schema];
  if[not validation`valid;
    :`success`data`error`recordCount!(0b; ();
      "Validation failed: ","; " sv validation`errors; 0)];

  typeMap:schema[`columns]!schema`types;
  typed:castColumns[filtered; typeMap; keepCols];
  if[99h = type typed;
    if[`error in key typed;
      :`success`data`error`recordCount!(0b; (); typed`error; 0)]];

  `success`data`error`recordCount!(1b; typed; ""; count typed)
 }

castColumns:{[tbl; typeMap; castCols]
  {[typeMap; t; col]
    casted:@[typeMap[col]$; t col; {[e] `FAIL}];
    if[`FAIL ~ casted; :`error!("Cast failed: ",string col)];
    ![t; (); 0b; (enlist col)!(enlist casted)]
  }[typeMap]/[tbl; castCols]
 }

/ ============================================================================
/ CONVENIENCE
/ ============================================================================

loadDefault:{[source; filepath] load[source; filepath; ","]}

loadStrict:{[source; filepath; delimiter]
  res:load[source; filepath; delimiter];
  if[not res`success; 'res`error];
  res`data
 }

\d .
