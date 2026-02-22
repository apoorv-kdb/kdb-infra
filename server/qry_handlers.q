/ qry_handlers.q
/ HTTP handlers for data query endpoints
/
/ POST /query/table
/   Request:  { field, measure, asofDate, prevDate, filters?, exclusions? }
/   Response: [{ <field>: <value>, asofValue, prevValue, change, changePct }]
/   One row per unique value of `field`, showing day-over-day comparison
/
/ POST /query/trend
/   Request:  { categoryField, measure, startDate, endDate, filters?, exclusions? }
/   Response: [{ date, category, value }]
/   One row per date × category combination within the date range
/
/ Date format: ISO "2024-02-12" (converted to kdb+ date internally)
/ Filters:     {"region": ["AMER","EMEA"], "product": ["WidgetA"]}
/ Exclusions:  same shape — values to exclude
/
/ Dependencies: catalog.q, cache.q

/ ============================================================================
/ INTERNAL HELPERS
/ ============================================================================

/ Parse ISO date string "2024-02-12" to kdb+ date
.qryHandler._parseDate:{[s]
  if[(::) ~ s; :0Nd];
  if[0 = count s; :0Nd];
  "D"$s   / kdb+ handles "2024-02-12" natively
 }

/ Apply include filters and exclusions to a table
/ filters:    dict of field symbol -> list of allowed string values
/ exclusions: dict of field symbol -> list of excluded string values
.qryHandler._applyFilters:{[tbl; filters; exclusions]
  / Include filters
  if[99h = type filters;
    {[tbl; field; vals]
      f:`$field;
      if[not f in cols tbl; :tbl];
      if[0 = count vals; :tbl];
      select from tbl where (value f) in `$vals
    }[tbl]'[string key filters; value filters]];

  / Exclusions
  if[99h = type exclusions;
    {[tbl; field; vals]
      f:`$field;
      if[not f in cols tbl; :tbl];
      if[0 = count vals; :tbl];
      select from tbl where not (value f) in `$vals
    }[tbl]'[string key exclusions; value exclusions]];

  tbl
 }

/ Parse filters/exclusions from JSON params
/ JSON sends {"region": ["AMER","EMEA"]} — comes through as dict of (string->list)
.qryHandler._parseFilters:{[params; key_]
  if[not key_ in key params; :(0#`)!()];
  raw:params key_;
  if[(::) ~ raw; :(0#`)!()];
  if[not 99h = type raw; :(0#`)!()];
  raw
 }

/ Aggregate a cached table by field+measure for a single date, with filters applied
/ Returns a keyed table: field -> measure sum
.qryHandler._aggForDate:{[data; field; measure; dt; filters; exclusions]
  dayData:select from data where date = dt;
  if[0 = count dayData; :(1!enlist (enlist field)!enlist `)]; / empty keyed table
  dayData:.qryHandler._applyFilters[dayData; filters; exclusions];
  if[0 = count dayData; :(1!enlist (enlist field)!enlist `)];
  ?[dayData; (); (enlist field)!enlist field;
    (enlist measure)!enlist (sum; measure)]
 }

/ ============================================================================
/ POST /query/table
/ ============================================================================

.qryHandler.table:{[params]
  if[not all `field`measure`asofDate`prevDate in key params;
    '"Missing required params: field, measure, asofDate, prevDate"];

  field:`$params`field;
  measure:`$params`measure;
  asofDate:.qryHandler._parseDate params`asofDate;
  prevDate:.qryHandler._parseDate params`prevDate;

  if[null asofDate; '"Invalid asofDate: ",params`asofDate];
  if[null prevDate; '"Invalid prevDate: ",params`prevDate];

  .catalog.require[field; `categorical];
  .catalog.require[measure; `value];

  tblSym:.catalog.tableFor field;
  cacheKey:`$string tblSym;
  if[not .cache.has cacheKey; '"Table not in cache: ",string tblSym];
  data:.cache.get cacheKey;

  filters:   .qryHandler._parseFilters[params; `filters];
  exclusions:.qryHandler._parseFilters[params; `exclusions];

  / Aggregate for each date
  asofAgg:.qryHandler._aggForDate[data; field; measure; asofDate; filters; exclusions];
  prevAgg:.qryHandler._aggForDate[data; field; measure; prevDate; filters; exclusions];

  / All unique field values across both dates
  allVals:asc distinct ((exec field from 0!asofAgg),(exec field from 0!prevAgg));

  / Build result rows — use actual field name as key (not "field_value")
  {[asofAgg; prevAgg; field; measure; fv]
    av:$[(enlist fv) in key asofAgg; `float$asofAgg[enlist fv; measure]; 0f];
    pv:$[(enlist fv) in key prevAgg; `float$prevAgg[enlist fv; measure]; 0f];
    chg:av - pv;
    pct:$[pv = 0f; 0f; chg % pv];
    (enlist field)!enlist[string fv],
    (`asofValue`prevValue`change`changePct)!(av; pv; chg; pct)
  }[asofAgg; prevAgg; field; measure;] each allVals
 }

/ ============================================================================
/ POST /query/trend
/ ============================================================================

.qryHandler.trend:{[params]
  if[not all `categoryField`measure`startDate`endDate in key params;
    '"Missing required params: categoryField, measure, startDate, endDate"];

  catField:`$params`categoryField;
  measure:`$params`measure;
  startDate:.qryHandler._parseDate params`startDate;
  endDate:.qryHandler._parseDate params`endDate;

  if[null startDate; '"Invalid startDate"];
  if[null endDate;   '"Invalid endDate"];

  .catalog.require[catField; `categorical];
  .catalog.require[measure; `value];

  tblSym:.catalog.tableFor catField;
  cacheKey:`$string tblSym;
  if[not .cache.has cacheKey; '"Table not in cache: ",string tblSym];
  data:.cache.get cacheKey;

  filters:   .qryHandler._parseFilters[params; `filters];
  exclusions:.qryHandler._parseFilters[params; `exclusions];

  / Filter to date window
  window:select from data where date within (startDate; endDate);
  if[0 = count window; :()];
  window:.qryHandler._applyFilters[window; filters; exclusions];
  if[0 = count window; :()];

  / Aggregate: sum measure by date × category
  agged:?[window; ();
    `date`category!(`date; catField);
    (enlist `value)!enlist (sum; measure)];
  agged:0!agged;

  / Return list of dicts with ISO date strings
  {`date`category`value!
    ((ssr[string x`date; "."; "-"]); string x`category; `float$x`value)} each agged
 }
