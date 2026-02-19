/ csv_loader.q
/ Load CSV files: read as strings, validate schema, type cast, return clean table
/ Looks up schema from validator registry
/ Dependencies: validator.q

/ ============================================================================
/ TYPE CASTING
/ ============================================================================

.csv.typeCast:{[tbl; typeMap]
  castCols:key typeMap;
  castVals:{[typeMap; tbl; col]
    typ:typeMap col;
    $[typ = "*";
      tbl col;
      typ in "Ss";
        `$tbl col;
      @[{[t; v] (t$)v}[typ]; tbl col;
        {[col; e] '"Cast failed: ",string[col],": ",e}[col]]]
  }[typeMap; tbl] each castCols;
  flip castCols!castVals
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

  / ensure delim is a char not a string
  delim:first delim;

  / read all columns as strings - one * per expected column
  raw:((count schema`columns)#"*"; enlist delim) 0: fp;

  expectedCols:schema`columns;
  keepCols:expectedCols where expectedCols in cols raw;
  if[0 = count keepCols; '"No expected columns found in file"];
  raw:keepCols#raw;

  / Cast first, then validate on typed data
 types:schema`types;
 typeMap:expectedCols!{x} each (count expectedCols)#types;
 typeMap:keepCols#typeMap;
  tbl:.csv.typeCast[raw; typeMap];

  validation:.validator.validateSchema[tbl; schema];
  if[not validation`valid;
    '"Validation failed: ","; " sv validation`errors];

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
