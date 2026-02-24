/ cat_handlers.q

/ GET /catalog/fields
/ Returns [{field, label, type, format}] where type = categorical|value
.catHandler.fields:{[params]
  tbl:select field, label, format, fieldType:role from .catalog.fields where role in `categorical`value;
  tbl  / .j.j serialises a table as a JSON array of objects
 }

/ GET /catalog/filter-options
/ Returns [{key, value}] flat list across all categorical fields
.catHandler.makeKV:{[fld; v] (`key`value)!(string fld; string v)}

.catHandler.getValsForField:{[fld]
  tbl:.catalog.tableFor fld;
  if[tbl=`; :()];
  ck:`$string tbl;
  data:$[.cache.has ck; .cache.get ck;
    @[{select from (value x)}; tbl; {0#([])}]];
  if[0 = count data; :()];
  if[not fld in cols data; :()];
  vals:asc distinct data fld;
  .catHandler.makeKV[fld;] each vals
 }

.catHandler.filterOptions:{[params]
  catFields:exec field from .catalog.fields where role=`categorical;
  if[0 = count catFields; :()];
  raze .catHandler.getValsForField each catFields
 }

show "  cat_handlers.q loaded"
