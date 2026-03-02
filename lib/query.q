/ lib/query.q
/ Reusable analytical query handlers.
/ Provides two analytical modes:
/   movement (.qryHandler.table)  — DoD/period comparison, two dates
/   spot      (.qryHandler.spot)  — single date, absolute values + composition %
/   trend     (.qryHandler.trend) — time series over a window
/ Dependencies: catalog.q, cache.q, filters.q

/ ============================================================================
/ SHARED UTILITIES
/ ============================================================================

.qryHandler.parseDate:{[s]
  if[(::) ~ s; :0Nd];
  if[0 = count s; :0Nd];
  "D"$s
 }

.qryHandler.applyInclude:{[tbl; fld; vals]
  if[not fld in cols tbl; :tbl];
  if[0 = count vals; :tbl];
  ?[tbl; enlist (in; fld; enlist `$vals); 0b; ()]
 }

.qryHandler.applyExclude:{[tbl; fld; vals]
  if[not fld in cols tbl; :tbl];
  if[0 = count vals; :tbl];
  ?[tbl; enlist (not; (in; fld; enlist `$vals)); 0b; ()]
 }

.qryHandler.stepInclude:{[state; k]
  t:state 0; d:state 1;
  ((.qryHandler.applyInclude[t; k; d k]); d)
 }

.qryHandler.stepExclude:{[state; k]
  t:state 0; d:state 1;
  ((.qryHandler.applyExclude[t; k; d k]); d)
 }

.qryHandler.applyFilters:{[tbl; filts; excls]
  if[99h = type filts; tbl:first .qryHandler.stepInclude/[(tbl; filts); key filts]];
  if[99h = type excls; tbl:first .qryHandler.stepExclude/[(tbl; excls); key excls]];
  tbl
 }

.qryHandler.getFilters:{[params; nm]
  if[not nm in key params; :(0#`)!()];
  raw:params nm;
  if[(::) ~ raw; :(0#`)!()];
  if[not 99h = type raw; :(0#`)!()];
  raw
 }

.qryHandler.getData:{[fld; meas]
  tblSym:.catalog.tableFor fld;
  ck:`$string tblSym;
  if[not .cache.has ck; '"Not cached: ",string tblSym];
  .cache.get ck
 }

/ ============================================================================
/ MOVEMENT — DoD / period comparison
/ POST /query/table
/ Params: field, measure, asofDate, prevDate, filters, exclusions
/ ============================================================================

.qryHandler.aggDate:{[data; fld; meas; dt; filts; excls]
  sub:?[data; enlist (=; `date; dt); 0b; ()];
  if[0 = count sub; :(0#`)!0#0f];
  sub:.qryHandler.applyFilters[sub; filts; excls];
  if[0 = count sub; :(0#`)!0#0f];
  agg:?[sub; (); (enlist fld)!enlist fld; (enlist meas)!enlist (sum; meas)];
  ((key agg)[fld])!((value agg)[meas])
 }

.qryHandler.buildRow:{[asofAgg; prevAgg; fld; meas; fv]
  av:`float$$[fv in key asofAgg; asofAgg fv; 0f];
  pv:`float$$[fv in key prevAgg; prevAgg fv; 0f];
  chg:av - pv;
  pct:$[pv = 0f; 0f; chg % pv];
  r:(enlist fld)!enlist string fv;
  r,(`asofValue`prevValue`change`changePct)!(av; pv; chg; pct)
 }

.qryHandler.table:{[params]
  if[not all `field`measure`asofDate`prevDate in key params;
    '"Missing params: field, measure, asofDate, prevDate"];
  fld:   `$params`field;
  meas:  `$params`measure;
  asofDt:.qryHandler.parseDate params`asofDate;
  prevDt:.qryHandler.parseDate params`prevDate;
  if[null asofDt; '"Invalid asofDate"];
  if[null prevDt; '"Invalid prevDate"];
  .catalog.require[fld; `categorical];
  .catalog.require[meas; `value];
  data:.qryHandler.getData[fld; meas];
  filts:.qryHandler.getFilters[params; `filters];
  excls:.qryHandler.getFilters[params; `exclusions];
  asofAgg:.qryHandler.aggDate[data; fld; meas; asofDt; filts; excls];
  prevAgg:.qryHandler.aggDate[data; fld; meas; prevDt; filts; excls];
  allVals:asc distinct ((key asofAgg),(key prevAgg));
  allVals:allVals where not null allVals;
  .qryHandler.buildRow[asofAgg; prevAgg; fld; meas;] each allVals
 }

/ ============================================================================
/ SPOT — single date, absolute values + composition %
/ POST /query/spot
/ Params: field, measure, asofDate, filters, exclusions, topN (optional)
/ ============================================================================

.qryHandler.spot:{[params]
  if[not all `field`measure`asofDate in key params;
    '"Missing params: field, measure, asofDate"];
  fld:   `$params`field;
  meas:  `$params`measure;
  dt:   .qryHandler.parseDate params`asofDate;
  topN:  $[`topN in key params; "I"$params`topN; 0i];
  if[null dt; '"Invalid asofDate"];
  .catalog.require[fld; `categorical];
  .catalog.require[meas; `value];
  data:.qryHandler.getData[fld; meas];
  filts:.qryHandler.getFilters[params; `filters];
  excls:.qryHandler.getFilters[params; `exclusions];
  agg:.qryHandler.aggDate[data; fld; meas; dt; filts; excls];
  agg:agg where not null key agg;
  if[0 = count agg; :()];
  total:sum value agg;
  rows:{[fld; meas; total; agg; fv]
    v:`float$$[fv in key agg; agg fv; 0f];
    pct:$[total = 0f; 0f; v % total];
    r:(enlist fld)!enlist string fv;
    r,(`value`pct)!(v; pct)
  }[fld; meas; total; agg] each key agg;
  / Sort by value descending
  rows:rows idesc {x`value} each rows;
  / Apply topN if specified
  $[topN > 0; topN#rows; rows]
 }

/ ============================================================================
/ TREND — time series
/ POST /query/trend
/ Params: categoryField, measure, startDate, endDate, filters, exclusions
/ ============================================================================

.qryHandler.buildTrendRow:{[r]
  `date`category`value!(ssr[string r`date; "."; "-"]; string r`category; `float$r`value)
 }

.qryHandler.trend:{[params]
  if[not all `categoryField`measure`startDate`endDate in key params;
    '"Missing params: categoryField, measure, startDate, endDate"];
  catFld: `$params`categoryField;
  meas:   `$params`measure;
  startDt:.qryHandler.parseDate params`startDate;
  endDt:  .qryHandler.parseDate params`endDate;
  if[null startDt; '"Invalid startDate"];
  if[null endDt;   '"Invalid endDate"];
  .catalog.require[catFld; `categorical];
  .catalog.require[meas; `value];
  data:.qryHandler.getData[catFld; meas];
  filts:.qryHandler.getFilters[params; `filters];
  excls:.qryHandler.getFilters[params; `exclusions];
  win:?[data; enlist (within; `date; (startDt; endDt)); 0b; ()];
  if[0 = count win; :()];
  win:.qryHandler.applyFilters[win; filts; excls];
  if[0 = count win; :()];
  agged:0!?[win; (); `date`category!(`date; catFld); (enlist `value)!enlist (sum; meas)];
  .qryHandler.buildTrendRow each agged
 }

show "  query.q loaded"
