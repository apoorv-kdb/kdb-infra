/ lib/catalog.q
/ CSV columns: app, table, field, label, type, role, format, enabled, source_field, date_format
/   role:         categorical | value | temporal
/   type:         symbol | float | long | date | timestamp
/   format:       currency | integer | percent | date | (empty)
/   source_field: raw source column name — empty means source already uses canonical name
/                 multiple rows per field = multiple accepted source aliases
/   date_format:  explicit date format for this source_field row — YYYY-MM-DD | YYYYMMDD | DD/MM/YYYY | MM/DD/YYYY
/                 empty means auto-detect (handles YYYY-MM-DD, YYYY.MM.DD, YYYYMMDD, DD/MM/YYYY)
/ Dependencies: none

/ ============================================================================
/ STATE
/ ============================================================================

/ Full catalog — one row per (field x source_field alias). Used for source mapping.
.catalog.raw:flip `app`table`field`label`type`role`format`enabled`source_field`date_format!10#enlist`$()

/ Unique fields — deduplicated to one row per (app x table x field). Used for UI + validation.
.catalog.fields:flip `app`table`field`label`type`role`format`enabled!8#enlist`$()

/ All fields — like .catalog.fields but ignores enabled flag. Used for ingestion (validate + cast).
/ Raw tables (e.g. sales_transactions) have enabled=0 to hide from UI but must still be validated.
.catalog.allFields:flip `app`table`field`label`type`role`format`enabled!8#enlist`$()

/ Source map per table: source_column_name -> canonical_field_name
/ Keyed by table symbol. Value is a string->symbol dict.
.catalog.sourceMap:()!()

/ Date format map — keyed by `table`source_field, value is format symbol.
/ Only entries with an explicit date_format in the catalog.
.catalog.dateFormatMap:()!()

/ ============================================================================
/ LOAD
/ ============================================================================

.catalog.load:{[path; app]
  raw:(("SSSSSSSBSS"; enlist ",") 0: hsym `$path);
  `.catalog.raw set raw;

  / UI fields — enabled=1 only, deduplicated. Used for frontend field picker.
  appRows:select from raw where enabled, app=`$string app;
  `.catalog.fields set 0! select by table, field from appRows;

  / Ingestion fields — all rows for this app, deduplicated. Used for validate + cast.
  / Includes enabled=0 tables (raw sources hidden from UI but needed for ingestion).
  allAppRows:select from raw where app=`$string app;
  `.catalog.allFields set 0! select by table, field from allAppRows;

  / Build source map — one dict per table, string sourceCol -> canonical symbol.
  / Built at top level (not inside lambda) to correctly update global .catalog.sourceMap.
  tblList:asc distinct exec table from allAppRows;
  smaps:{[rows; tbl]
    tblRows:select from rows where table = tbl;
    / Rows with explicit source_field alias
    mapped:  select from tblRows where not null source_field, source_field <> `$"";
    / Rows where source name = canonical name (no alias needed)
    unmapped:select from tblRows where (null source_field) | source_field = `$"";
    srcDict:(string mapped`source_field)!mapped`field;
    idDict: (string unmapped`field)!unmapped`field;
    / Explicit mappings take priority over identity mappings
    idDict,srcDict
  }[allAppRows] each tblList;
  `.catalog.sourceMap set tblList!smaps;

  / Build date format map — keyed by `table`field (canonical), value is format symbol.
  / Cast runs after rename so we key on canonical field name, not source_field.
  / If multiple source aliases for the same field have different date_formats,
  / the last one wins — this should be avoided in practice (same field = same format).
  / Only populated for rows where date_format is explicitly set.
  fmtRows:select from allAppRows where not null date_format, date_format <> `$"";
  fmtKeys:{` sv x} each flip (fmtRows`table; fmtRows`field);
  `.catalog.dateFormatMap set fmtKeys!fmtRows`date_format;

  show "  Catalog: ",string[count .catalog.fields]," fields loaded for app '",string[app],"'";
 }

.catalog.reload:{[path; app] .catalog.load[path; app]}

/ ============================================================================
/ SOURCE FIELD RENAME
/ ============================================================================

/ Rename columns in a raw table from source names to canonical names.
/ Drops any columns not in the catalog for this table.
.catalog.rename:{[tblName; raw]
  if[not tblName in key .catalog.sourceMap;
    show "  [WARN] No source map for table: ",string tblName;
    :raw];
  smap:.catalog.sourceMap tblName;
  / Only keep columns that have a mapping
  srcCols:cols raw;
  keepSrc:srcCols where (string srcCols) in key smap;
  if[0 = count keepSrc;
    '"catalog.rename: no mapped columns found in table ",string tblName];
  / Rename: symbol cols -> string -> look up in smap -> new symbol col names
  newCols:smap string keepSrc;
  flip newCols!flip[keepSrc#raw] keepSrc
 }

/ ============================================================================
/ VALIDATION
/ ============================================================================

/ Validate a renamed table against catalog for a given app+table.
/ Blocking:     missing columns -> sets valid:0b
/ Non-blocking: null counts logged as warnings only
/ Returns: `valid`errors`warnings!(bool; errors; warnings)
.catalog.validate:{[tblName; tbl; appName]
  fields:select from .catalog.allFields where app=appName, table=tblName;
  expected:exec field from fields;
  errors:();

  / Blocking: required columns must exist
  missing:expected where not expected in cols tbl;
  if[count missing;
    errors,:enlist "Missing columns: ",", " sv string missing];

  / Non-blocking: null warnings printed to console
  present:expected where expected in cols tbl;
  {[tbl; tblName; col]
    vals:tbl col;
    n:$[11h=type vals; sum vals=`; 10h=type vals; sum vals=""; sum null vals];
    if[n>0; show "  [WARN] ",string[col]," has ",string[n]," nulls (",string[tblName],")"]
  }[tbl; tblName] each present;

  `valid`errors`warnings!((0=count errors); errors; ())
 }

/ ============================================================================
/ TYPE CASTING
/ ============================================================================

/ Normalise a single date string to YYYY-MM-DD before casting.
/ fmt: explicit format symbol, or ` for auto-detect.
/ Supported formats: `YYYYMMDD  `DDMMYYYY  `MMDDYYYY  `YYYYMMDD  (auto tries YYYYMMDD then DD/MM/YYYY)
.catalog.normDate:{[fmt; s]
  n:count s;
  $[
    fmt = `YYYYMMDD;
      s[0 1 2 3],"-",s[4 5],"-",s[6 7];
    fmt = `DDMMYYYY;
      s[4 5 6 7],"-",s[2 3],"-",s[0 1];
    fmt = `MMDDYYYY;
      s[4 5 6 7],"-",s[0 1],"-",s[2 3];
    / Auto-detect: try YYYYMMDD then DD/MM/YYYY then pass through
    (n=8) and all s in "0123456789";
      s[0 1 2 3],"-",s[4 5],"-",s[6 7];
    (n=10) and (s[2]="/") and (s[5]="/");
      s[6 7 8 9],"-",s[3 4],"-",s[0 1];
    s   / pass through — "D"$ handles YYYY-MM-DD and YYYY.MM.DD natively
  ]
 }

/ Cast a table's columns to types defined in catalog.
/ Uses allFields so enabled=0 tables (raw sources) are still cast correctly.
.catalog.cast:{[tblName; tbl; appName]
  fields:select from .catalog.allFields where app=appName, table=tblName;
  if[0 = count fields; :tbl];
  typeMap:(exec field from fields)!fields[`type];
  castCols:exec field from fields where field in cols tbl;
  {[typeMap; tblNm; tbl; col]
    if[not col in key typeMap; :tbl];
    t:typeMap col;
    tbl[col]:$[
      t = `symbol;    `$tbl col;
      t = `float;     "F"$tbl col;
      t = `long;      "J"$tbl col;
      t = `int;       "I"$tbl col;
      t = `date;
        ["D"$.catalog.normDate[
          $[(` sv tblNm,col) in key .catalog.dateFormatMap;
            .catalog.dateFormatMap ` sv tblNm,col;
            `];
        ] each tbl col];
      t = `timestamp; "P"$tbl col;
      tbl col
    ];
    tbl
  }[typeMap; tblName]/[tbl; castCols]
 }

/ ============================================================================
/ LOOKUPS
/ ============================================================================

.catalog.byRole:{[role] select from .catalog.fields where role=role}

.catalog.meta:{[field]
  res:select from .catalog.fields where field=field;
  $[count res; first res; ()!()]
 }

.catalog.tableFor:{[field]
  m:.catalog.meta field;
  $[count m; m`table; `]
 }

.catalog.typeOf:{[field]
  m:.catalog.meta field;
  $[count m; m`type; `]
 }

/ ============================================================================
/ VALIDATION HELPERS
/ ============================================================================

.catalog.isKnown:{[field]
  0 < count select from .catalog.fields where field=field
 }

.catalog.isRole:{[field; role]
  0 < count select from .catalog.fields where field=field, role=role
 }

.catalog.require:{[field; role]
  if[not .catalog.isKnown field; '"Unknown field: ",string field];
  if[not .catalog.isRole[field; role];
    actual:exec first role from .catalog.fields where field=field;
    '"Field '",string[field],"' has role '",string[actual],"' not '",string[role],"'"];
 }

/ ============================================================================
/ JSON HELPERS
/ ============================================================================

.catalog.sanitise:{[row]
  {$[null v:x; $[0h > abs type v; 0; ""]; v]} each row
 }

.catalog.sanitiseTable:{[tbl]
  if[0 = count tbl; :tbl];
  .catalog.sanitise each tbl
 }

show "  catalog.q loaded"
