/ csv_loader.q
/ Load CSV files: read as strings → validate schema → type cast → return clean table
/ Looks up schema from validator registry
/
/ Dependencies: validator.q

\d .csv

/ ============================================================================
/ MAIN LOAD FUNCTION
/ ============================================================================

/ Load a CSV file with validation and type casting
/ Args:
/   source: symbol - source name (must have schema registered in validator)
/   filepath: symbol or string - path to CSV file
/   delimiter: char - CSV delimiter (default ",")
/ Returns: typed table (or throws on failure)
load:{[source; filepath; delimiter]
  fp:$[-11h = type filepath; filepath; hsym `$filepath];

  / Check file exists
  if[() ~ key fp; '"File not found: ",string fp];

  / Look up schema
  schema:.validator.getSchema[source];
  if[(::) ~ schema; '"No schema registered for source: ",string source];

  / Load as strings (all columns as strings)
  raw:("*"; enlist delimiter) 0: fp;

  / Filter to expected columns only (drop extras)
  expectedCols:schema`columns;
  keepCols:expectedCols where expectedCols in cols raw;
  if[0 = count keepCols; '"No expected columns found in file"];
  raw:keepCols#raw;

  / Validate
  validation:.validator.validateSchema[raw; schema];
  if[not validation`valid;
    '"Validation failed: ","; " sv validation`errors];

  / Type cast
  types:schema`types;
  typeMap:expectedCols!types;
  typeMap:keepCols#typeMap;
  tbl:typeCast[raw; typeMap];

  tbl
 }

/ ============================================================================
/ TYPE CASTING
/ ============================================================================

/ Cast columns from strings to target types
/ Args: tbl (table), typeMap (dict of col -> type char)
/ Returns: typed table
typeCast:{[tbl; typeMap]
  castCols:key typeMap;
  {[tbl; col; typeMap]
    typ:typeMap col;
    if[typ = "*"; :tbl];  / Skip string columns
    casted:@[{[t; v] t$v}[typ]; tbl col;
      {[col; e] '"Cast failed: ",string col}[col]];
    ![tbl; (); 0b; (enlist col)!(enlist casted)]
  }[; ; typeMap]/[tbl; castCols]
 }

/ ============================================================================
/ CONVENIENCE
/ ============================================================================

loadDefault:{[source; filepath] load[source; filepath; ","]}

loadStrict:{[source; filepath; delimiter]
  res:@[load; (source; filepath; delimiter); {[e] `error`msg!(1b; e)}];
  if[99h = type res; 'res`msg];
  res
 }

\d .
