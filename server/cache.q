/ cache.q
/ Server-side cache management
/ Loads tables from the partitioned DB, optionally transforms them,
/ holds in memory, and refreshes on a timer
/
/ Each cached table is registered as a "recipe" - table name, date horizon,
/ and optional transform function. On refresh, all recipes are replayed.
/
/ Dependencies: db_writer.q (for dbPath and reload)

\d .cache

/ ============================================================================
/ STATE
/ ============================================================================

/ Cached data: name (symbol) -> table data
data:()!()

/ Recipes: name (symbol) -> dict with `table`horizonDays`transformFn
recipes:()!()

/ Cache refresh interval in ms
refreshMs:600000

/ Last refresh timestamp
lastRefresh:0Np

/ ============================================================================
/ REGISTRATION
/ ============================================================================

/ Register a table to be cached
/ Args:
/   name: symbol - cache key (can differ from table name)
/   table: symbol - table name in partitioned DB
/   horizonDays: int - how many days back to load from DB
/   transformFn: function or (::) - {[data] ...} applied after load, (::) for none
register:{[name; table; horizonDays; transformFn]
  .cache.recipes[name]:`table`horizonDays`transformFn!(table; horizonDays; transformFn);
 }

/ Remove a cached table
remove:{[name]
  .cache.recipes _: name;
  .cache.data _: name;
 }

/ ============================================================================
/ LOADING
/ ============================================================================

/ Load a single cached table by name
/ Reads from DB, applies transform if registered, stores in .cache.data
loadOne:{[name]
  if[not name in key recipes; '"Unknown cache entry: ",string name];

  recipe:recipes name;
  tbl:recipe`table;
  horizon:recipe`horizonDays;
  fn:recipe`transformFn;

  cutoff:.z.d - horizon;

  / Load from partitioned DB
  raw:@[{[t; c] select from t where date >= c}; (tbl; cutoff);
    {[e] show "Cache load failed for ",e; 0#([])}];

  / Apply transform if provided
  result:$[(::) ~ fn; raw; @[fn; raw; {[e] show "Cache transform failed: ",e; raw}]];

  .cache.data[name]:result;
  show "  Cached ",string[name],": ",string[count result]," rows";
 }

/ Load all registered cached tables
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

/ Get a cached table by name
/ Args: name (symbol)
/ Returns: table (or throws if not found)
get:{[name]
  if[not name in key data; '"Not cached: ",string name];
  data name
 }

/ Check if a name is cached
has:{[name] name in key data}

/ List all cached tables with metadata
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

/ Refresh all cached tables (reload from DB and re-apply transforms)
refresh:{[]
  loadAll[];
 }

/ Start automatic cache refresh on a timer
startRefresh:{[ms]
  `.cache.refreshMs set ms;
  .z.ts:{.cache.refresh[]};
  system "t ",string ms;
  show "Cache refresh timer started: ",string[ms],"ms";
 }

/ Stop cache refresh timer
stopRefresh:{[]
  system "t 0";
  show "Cache refresh timer stopped.";
 }

/ ============================================================================
/ ON-DEMAND QUERIES (uncached / drill-down)
/ ============================================================================

/ Load directly from partitioned DB without caching
/ For drill-down queries on detail tables
/ Args:
/   table: symbol - table name
/   asOfDate: date - find max date <= this
/ Returns: dict `current`previous`currentDate`previousDate
drillDown:{[table; asOfDate]
  dates:availableDates[table];
  currentDate:$[0 = count dates; 0Nd; last dates where dates <= asOfDate];
  previousDate:$[null currentDate; 0Nd; last dates where dates < currentDate];

  current:$[null currentDate; 0#value table;
    select from table where date = currentDate];

  previous:$[null previousDate; 0#value table;
    select from table where date = previousDate];

  `current`previous`currentDate`previousDate!(current; previous; currentDate; previousDate)
 }

/ Get available dates for a table in the partitioned DB
availableDates:{[table]
  dbPath:.dbWriter.dbPath;
  allDates:asc "D"$string key dbPath;
  allDates:allDates where not null allDates;
  allDates where {[dbPath; tbl; dt]
    tbl in key ` sv dbPath , `$string dt
  }[dbPath; table] each allDates
 }

\d .
