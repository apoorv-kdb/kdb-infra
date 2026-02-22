/ cat_handlers.q
/ HTTP handlers for catalog endpoints
/
/ GET /catalog/fields
/   Returns all enabled fields as [{field,label,type,format}]
/   'type' is the role value ('categorical'|'value') to match frontend CatalogField interface
/
/ GET /catalog/filter-options
/   Returns ALL categorical field distinct values as flat [{key,value}]
/   key = field name, value = field value (string)
/   No params required — returns everything so frontend can populate all dropdowns in one call
/
/ Dependencies: catalog.q, cache.q

/ GET /catalog/fields
.catHandler.fields:{[params]
  / Return field + label + role-as-type (matches frontend CatalogField interface)
  / Exclude temporal fields — frontend doesn't need them in FieldPicker
  tbl:select from .catalog.fields where role in `categorical`value;
  / Frontend CatalogField.type = 'categorical' | 'value' — we map role -> type
  rows:{x!y x}[`field`label`format;] each tbl;
  / Inject 'type' as the role value so frontend FieldPicker can distinguish dimensions from measures
  rows:{[row; role] row,enlist[`type]!enlist role}[;] ./: flip (rows; exec role from tbl);
  rows
 }

/ GET /catalog/filter-options
/ Returns all distinct values across all categorical fields
/ Flat list: [{key:"region", value:"AMER"}, ...]
.catHandler.filterOptions:{[params]
  catFields:exec field from .catalog.fields where role=`categorical;
  if[0 = count catFields; :()];

  raze {[field]
    tbl:.catalog.tableFor field;
    if[tbl=`; :()];

    / Prefer cache; fall back to direct table query
    cacheKey:`$string tbl;
    data:$[.cache.has cacheKey;
      .cache.get cacheKey;
      @[{select from (value x)}; tbl; {[e] 0#([])}]];

    if[0 = count data; :()];
    if[not field in cols data; :()];

    vals:asc distinct data field;
    ([] key: count[vals]#enlist string field; value: string each vals)
  } each catFields
 }
