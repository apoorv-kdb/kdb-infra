/ cache.q
/ Server-side cache management
/ Loads tables from the partitioned DB, optionally transforms them,
/ holds in memory, and refreshes on a timer
/ Dependencies: db_writer.q (for dbPath and reload)

/ ============================================================================
/ STATE
/ ============================================================================

.cache.cacheData:()!()
.cache.recipes:()!()
.cache.refreshMs:600000
.cache.lastRefresh:0Np

/ ============================================================================
/ REGISTRATION
/ ============================================================================

.cache.register:{[nm; tblName; horizonDays; transformFn]
  .cache.recipes[nm]:`tblName`horizonDays`transformFn!(tblName; horizonDays; transformFn);
 }

.cache.remove:{[nm]
  .cache.recipes _: nm;
  .cache.cacheData _: nm;
 }

/ ============================================================================
/ LOADING
/ ============================================================================

.cache.loadOne:{[nm]
  if[not nm in key .cache.recipes; '"Unknown cache entry: ",string nm];

  recipe:.cache.recipes nm;
  tblName:recipe`tblName;
  horizon:recipe`horizonDays;
  fn:recipe`transformFn;

  cutoff:.z.d - horizon;

  raw:.[{[t; c] select from t where date >= c}; (tblName; cutoff);
    {[e] show "Cache load failed: ",e; 0#([])}];

  result:$[(::) ~ fn; raw; @[fn; raw; {[e] show "Cache transform failed: ",e; raw}]];

  .cache.cacheData[nm]:result;
  show "  Cached ",string[nm],": ",string[count result]," rows";
 }

.cache.loadAll:{[]
  show "Loading cache...";
  .dbWriter.reload[];
  .cache.loadOne each key .cache.recipes;
  `.cache.lastRefresh set .z.p;
  show "Cache loaded at ",string .z.p;
 }

/ ============================================================================
/ ACCESS
/ ============================================================================

.cache.get:{[nm]
  if[not nm in key .cache.cacheData; '"Not cached: ",string nm];
  .cache.cacheData nm
 }

.cache.has:{[nm] nm in key .cache.cacheData}

.cache.cacheList:{[]
  if[0 = count .cache.recipes; :([] nm:`$(); tblName:`$(); horizonDays:`int$(); rows:`long$(); hasTransform:`boolean$())];
  names:key .cache.recipes;
  ([] nm:names;
    tblName:{.cache.recipes[x]`tblName} each names;
    horizonDays:{.cache.recipes[x]`horizonDays} each names;
    rows:{$[x in key .cache.cacheData; count .cache.cacheData x; 0]} each names;
    hasTransform:{not (::) ~ .cache.recipes[x]`transformFn} each names)
 }

/ ============================================================================
/ REFRESH
/ ============================================================================

.cache.refresh:{[] .cache.loadAll[]}

.cache.startRefresh:{[ms]
  `.cache.refreshMs set ms;
  .z.ts:{.cache.refresh[]};
  system "t ",string ms;
  show "Cache refresh timer started: ",string[ms],"ms";
 }

.cache.stopRefresh:{[]
  system "t 0";
  show "Cache refresh timer stopped.";
 }

/ ============================================================================
/ ON-DEMAND QUERIES (for drill-down into uncached detail)
/ ============================================================================

.cache.drillDown:{[tblName; asOfDate]
  .dbWriter.reload[];
  dates:asc distinct ?[tblName; (); (); (enlist `d)!(enlist `date)] `d;
  currentDate:.dates.asOf[dates; asOfDate];
  previousDate:.dates.prev[dates; currentDate];

  current:$[null currentDate; 0#([]); select from tblName where date = currentDate];
  previous:$[null previousDate; 0#([]); select from tblName where date = previousDate];

  `current`previous`currentDate`previousDate!(current; previous; currentDate; previousDate)
 }
