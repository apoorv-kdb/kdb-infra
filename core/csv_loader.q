/ csv_loader.q
/ Load CSV files: read as strings, validate schema, type cast, return clean table
/ Looks up schema from validator registry
/ Dependencies: validator.q

/ ============================================================================
/ TYPE CASTING
/ ============================================================================

.csv.typeCast:{[tbl; typeMap]
  castCols:key typeMap;
  {[typeMap; tbl; col]
    typ:typeMap col;
    if[typ = "*"; :tbl];
    casted:@[{[t; v] t$v}[typ]; tbl col;
      {[col; e] '"Cast failed: ",string col}[col]];
    ![tbl; (); 0b; (enlist col)!(enlist casted)]
  }[typeMap]/[tbl; castCols]
 }

/ ============================================================================
/ MAIN LOAD FUNCTION
/ ============================================================================

/ Load a CSV file with validation and type casting
/ Args:
/   src: symbol - source name (must have schema registered in validator)
/   filepath: symbol or string - path to CSV file
/   delim: char - CSV delimiter (default ",")
/ Returns: typed table (or throws on failure)
.csv.loadCSV:{[src; filepath; delim]
  fp:$[-11h = type filepath; filepath; hsym `$filepath];

  if[() ~ key fp; '"File not found: ",string fp];

  schema:.validator.getSchema[src];
  if[(::) ~ schema; '"No schema registered for source: ",string src];

  raw:("*"; enlist delim) 0: fp;

  expectedCols:schema`columns;
  keepCols:expectedCols where expectedCols in cols raw;
  if[0 = count keepCols; '"No expected columns found in file"];
  raw:keepCols#raw;

  validation:.validator.validateSchema[raw; schema];
  if[not validation`valid;
    '"Validation failed: ","; " sv validation`errors];

  types:schema`types;
  typeMap:expectedCols!types;
  typeMap:keepCols#typeMap;
  tbl:.csv.typeCast[raw; typeMap];

  tbl
 }

/ ============================================================================
/ CONVENIENCE
/ ============================================================================

.csv.loadDefault:{[src; filepath] .csv.loadCSV[src; filepath; ","]}

.csv.loadStrict:{[src; filepath; delim]
  res:@[.csv.loadCSV; (src; filepath; delim); {[e] `error`msg!(1b; e)}];
  if[99h = type res; 'res`msg];
  res
 }
