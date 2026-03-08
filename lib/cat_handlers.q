/ lib/cat_handlers.q
/ HTTP handlers for catalog and init endpoints.
/ Dependencies: catalog.q, cache.q

/ ============================================================================
/ INIT - unified startup response
/ GET /api/sales/init
/ Returns everything the frontend needs on load:
/   latestAsofDate, defaultPrevDate, catalogFields, filterOptions, presets
/ ============================================================================

.catHandler.latestDate:{[]
  partitions:key .dbWriter.dbPath;
  if[0 = count partitions; :""];
  dates:partitions where {not null "D"$string x} each partitions;
  if[0 = count dates; :""];
  ssr[string last asc dates; "."; "-"]
 }

.catHandler.defaultPrevDate:{[latestStr]
  if[0 = count latestStr; :""];
  dt:"D"$latestStr;
  p:dt - 30;
  ssr[string p; "."; "-"]
 }

.catHandler.init:{[params]
  latest:.catHandler.latestDate[];
  pd:.catHandler.defaultPrevDate[latest];
  fields:.catHandler.fields[params];
  opts:.catHandler.filterOptions[params];
  `latestAsofDate`defaultPrevDate`catalogFields`filterOptions`presets!(
    latest; pd; fields; opts; ())
 }

/ ============================================================================
/ CATALOG FIELDS
/ GET /api/sales/catalog/fields (also called by init)
/ Returns enabled fields - dimensions and measures only (not temporal)
/ ============================================================================

.catHandler.fields:{[params]
  select field, label, format, fieldType:role
    from .catalog.fields
    where role in `categorical`value
 }

/ ============================================================================
/ FILTER OPTIONS
/ GET /api/sales/catalog/filter-options (also called by init)
/ Returns [{key, value}] across all categorical fields
/ ============================================================================

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
