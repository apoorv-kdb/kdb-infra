/ core/csv_loader.q
/ Load CSV files using catalog for column mapping, renaming, and type casting.
/ Dependencies: catalog.q

.csv.loadCSV:{[tblName; appName; filepath; delim]
  fp:$[":"=first string filepath; filepath; hsym filepath];
  if[() ~ key fp; '"File not found: ",string fp];

  delim:first delim;

  / Read all lines as strings
  rawLines:read0 fp;
  if[0 = count rawLines; '"Empty file: ",string fp];

  / Parse header from first line, strip \r if present (Windows line endings)
  hdr:`$delim vs {x where not x="\r"} first rawLines;

  / Parse each data row — strip \r, split on delimiter, map to header
  dataLines:1_ rawLines;
  dataLines:{x where not x="\r"} each dataLines;
  raw:hdr!(flip (delim vs) each dataLines);
  raw:flip raw;

  / Rename source columns -> canonical, drop unmapped
  renamed:.catalog.rename[tblName; raw];

  / Cast to catalog types
  casted:.catalog.cast[tblName; renamed; appName];

  casted
 }

.csv.loadDefault:{[tblName; appName; filepath]
  .csv.loadCSV[tblName; appName; filepath; ","]
 }

show "  csv_loader.q loaded"
