/ core/csv_loader.q
/ Load CSV files using catalog for column mapping, renaming, and type casting.
/ Dependencies: catalog.q

/ Parse a single CSV line, correctly handling quoted fields with embedded delimiters.
/ Strips \r for Windows line endings.
.csv.splitLine:{[delim; line]
  line:{x where not x="\r"} line;
  fields:();
  cur:"";
  inQuote:0b;
  i:0;
  while[i < count line;
    c:line i;
    $[inQuote;
      $[c="\""; inQuote:0b; cur:cur,c];
      $[c=delim; [fields:fields,enlist cur; cur:""];
        c="\""; inQuote:1b;
        cur:cur,c]
    ];
    i+:1];
  fields,enlist cur
 }

.csv.loadCSV:{[tblName; appName; filepath; delim]
  fp:$[":"=first string filepath; filepath; hsym filepath];
  if[() ~ key fp; '"File not found: ",string fp];

  delim:first delim;

  / Read all lines as strings
  rawLines:read0 fp;
  if[0 = count rawLines; '"Empty file: ",string fp];

  / Parse header from first line, strip \r if present (Windows line endings)
  hdr:`$delim vs {x where not x="\r"} first rawLines;

  / Parse each data row respecting quoted fields with embedded delimiters
  dataLines:1_ rawLines;
  parsed:.csv.splitLine[delim;] each dataLines;
  raw:flip hdr!flip parsed;

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
