/ qry_handlers.q

.qryHandler.parseDate:{[s]
  if[(::) ~ s; :0Nd];
  if[0 = count s; :0Nd];
  "D"$s
 }

.qryHandler.applyInclude:{[tbl; fld; vals]
  if[not fld in cols tbl; :tbl];
  if[0 = count vals; :tbl];
  select from tbl where (value fld) in `$vals
 }

.qryHandler.applyExclude:{[tbl; fld; vals]
  if[not fld in cols tbl; :tbl];
  if[0 = count vals; :tbl];
  select from tbl where not (value fld) in `$vals
 }

/ Accumulator carries (tbl; dict) pair so no free variables needed in lambda
.qryHandler.stepInclude:{[state; k]
  t:state 0; d:state 1;
  ((.qryHandler.applyInclude[t; k; d k]); d)
 }

.qryHandler.stepExclude:{[state; k]
  t:state 0; d:state 1;
  ((.qryHandler.applyExclude[t; k; d k]); d)
 }

.qryHandler.applyFilters:{[tbl; filts; excls]
  if[99h = type filts;
    tbl:first .qryHandler.stepInclude/[(tbl; filts); key filts]];
  if[99h = type excls;
    tbl:first .qryHandler.stepExclude/[(tbl; excls); key excls]];
  tbl
 }

.qryHandler.getFilters:{[params; nm]
  if[not nm in key params; :(0#`)!()];
  raw:params nm;
  if[(::) ~ raw; :(0#`)!()];
  if[not 99h = type raw; :(0#`)!()];
  raw
 }

.qryHandler.aggDate:{[data; fld; meas; dt; filts; excls]
  sub:select from data where date = dt;
  if[0 = count sub; :(0#`)!0#0f];
  sub:.qryHandler.applyFilters[sub; filts; excls];
  if[0 = count sub; :(0#`)!0#0f];
  / Return simple dict: fv -> measure sum
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
  tblSym:.catalog.tableFor fld;
  ck:`$string tblSym;
  if[not .cache.has ck; '"Not cached: ",string tblSym];
  data:.cache.get ck;
  filts:.qryHandler.getFilters[params; `filters];
  excls:.qryHandler.getFilters[params; `exclusions];
  asofAgg:.qryHandler.aggDate[data; fld; meas; asofDt; filts; excls];
  prevAgg:.qryHandler.aggDate[data; fld; meas; prevDt; filts; excls];
  allVals:asc distinct ((key asofAgg),(key prevAgg));
  .qryHandler.buildRow[asofAgg; prevAgg; fld; meas;] each allVals
 }

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
  tblSym:.catalog.tableFor catFld;
  ck:`$string tblSym;
  if[not .cache.has ck; '"Not cached: ",string tblSym];
  data:.cache.get ck;
  filts:.qryHandler.getFilters[params; `filters];
  excls:.qryHandler.getFilters[params; `exclusions];
  win:select from data where date within (startDt; endDt);
  if[0 = count win; :()];
  win:.qryHandler.applyFilters[win; filts; excls];
  if[0 = count win; :()];
  agged:0!?[win; (); `date`category!(`date; catFld); (enlist `value)!enlist (sum; meas)];
  .qryHandler.buildTrendRow each agged
 }

show "  qry_handlers.q loaded"
