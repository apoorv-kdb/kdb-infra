/ lib/cat_handlers.q
/ HTTP handlers for catalog endpoints.
/ Dependencies: catalog.q, cache.q

/ GET /catalog/fields
/ Returns enabled fields for UI — dimensions and measures only (not temporal)
.catHandler.fields:{[params]
  select field, label, format, fieldType:role
    from .catalog.fields
    where role in `categorical`value
 }

/ GET /catalog/filter-options
/ Returns [{key, value}] across all categorical fields
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
  / Handle symbol, string, and other types for null filtering
  vals:$[11h=abs type vals; vals where vals<>`;
         10h=abs type vals; vals where not vals=\:"";
         vals where not null vals];
  .catHandler.makeKV[fld;] each vals
 }

.catHandler.filterOptions:{[params]
  catFields:exec field from .catalog.fields where role=`categorical;
  if[0 = count catFields; :()];
  raze .catHandler.getValsForField each catFields
 }

show "  cat_handlers.q loaded"
