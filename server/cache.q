/ cache.q
/ Server-side cache management
/ Loads tables from the partitioned DB, optionally transforms them,
/ holds in memory, and refreshes on a timer
/
/ Dependencies: db_writer.q (for dbPath and reload)

\d .cache

/ ============================================================================
/ STATE
/ ============================================================================

data:()!()
recipes:()!()
refreshMs:600000
lastRefresh:0Np

/ ============================================================================
/ REGISTRATION
/ ============================================================================

register:{[name; table; horizonDays; transformFn]
  .cache.recipes[name]:`table`horizonDays`transformFn!(table; horizonDays; transformFn);
 }

remove:{[name]
  .cache.recipes _: name;
  .cache.data _: name;
 }

/ ============================================================================
/ LOADING
/ ============================================================================

loadOne:{[name]
  if[not name in key recipes; '"Unknown cache entry: ",string name];

  recipe:recipes name;
  tbl:recipe`table;
  horizon:recipe`horizonDays;
  fn:recipe`transformFn;

  cutoff:.z.d - horizon;

  raw:@[{[t; c] select from t where date >= c}; (tbl; cutoff);
    {[e] show "Cache load failed: ",e; 0#([])}];

  result:$[(::) ~ fn; raw; @[fn; raw; {[e] show "Cache transform failed: ",e; raw}]];

  .cache.data[name]:result;
  show "  Cached ",string[name],": ",string[count result]," rows";
 }

loadAll:{[]
  show "Loading cache...";
  .dbWriter.reload[];
  loadOne each key recipes;
  `.cache.lastRefresh set .z.p;
  show "Cache loaded at ",string .z.p;
 }

/ ============================================================================
/ ACCESS
/ ============================================================================

get:{[name]
  if[not name in key data; '"Not cached: ",string name];
  data name
 }

has:{[name] name in key data}

list:{[]
  if[0 = count recipes; :([] name:`$(); table:`$(); horizonDays:`int$(); rows:`long$(); hasTransform:`boolean$())];
  names:key recipes;
  ([] name:names;
    table:{.cache.recipes[x]`table} each names;
    horizonDays:{.cache.recipes[x]`horizonDays} each names;
    rows:{$[x in key .cache.data; count .cache.data x; 0]} each names;
    hasTransform:{not (::) ~ .cache.recipes[x]`transformFn} each names)
 }

/ ============================================================================
/ REFRESH
/ ============================================================================

refresh:{[] loadAll[]}

startRefresh:{[ms]
  `.cache.refreshMs set ms;
  .z.ts:{.cache.refresh[]};
  system "t ",string ms;
  show "Cache refresh timer started: ",string[ms],"ms";
 }

stopRefresh:{[]
  system "t 0";
  show "Cache refresh timer stopped.";
 }

/ ============================================================================
/ ON-DEMAND QUERIES (for drill-down into uncached detail)
/ ============================================================================

drillDown:{[tableName; asOfDate]
  .dbWriter.reload[];
  dates:asc distinct ?[tableName; (); (); (enlist `d)!(enlist `date)] `d;
  currentDate:.dates.asOf[dates; asOfDate];
  previousDate:.dates.prev[dates; currentDate];

  current:$[null currentDate; 0#([]); select from tableName where date = currentDate];
  previous:$[null previousDate; 0#([]); select from tableName where date = previousDate];

  `current`previous`currentDate`previousDate!(current; previous; currentDate; previousDate)
 }

\d .
