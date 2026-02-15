/ inv domain — server.q
/ Single server for inventory domain, serving data from positions + movements apps
/ Start with: q apps/inv/server.q -p 5002 -dbPath /data/databases/prod

\l server/server_init.q

/ Load all inv app configs (registers schemas + domain)
loadDomainConfigs[`inv];

/ ============================================================================
/ CACHE RECIPES
/ ============================================================================

/ From positions app: detail + aggregations
.cache.register[`positions;   `inv_positions;    90;  ::];
.cache.register[`by_category; `inv_by_category;  365; ::];

/ From positions app: warehouse trend with rolling stats
.cache.register[`wh_trend; `inv_by_warehouse; 365;
  {[d]
    d:.rolling.addRolling[d; `total_value; 30; `avg; `value_30d_avg];
    d:.rolling.addRolling[d; `total_units; 30; `avg; `units_30d_avg];
    d
  }];

/ From positions app: category hierarchy (flatten from detail)
.cache.register[`cat_hierarchy; `inv_positions; 365;
  {[d] .hierarchy.flatten[d; `category`subcategory; `units`value; enlist `date]}];

/ From movements app: movement aggregation
.cache.register[`movements; `inv_movement_by_warehouse; 365; ::];

/ For DoD comparison
.cache.register[`wh_compare; `inv_by_warehouse; 365; ::];

.cache.loadAll[]
.cache.startRefresh[600000]

/ ============================================================================
/ QUERY API
/ ============================================================================

/ Warehouse summary with rolling averages
getByWarehouse:{[dt]
  select from .cache.get[`wh_trend] where date = dt
 }

/ Warehouse trend over time
getWarehouseTrend:{[wh; startDt; endDt]
  select from .cache.get[`wh_trend]
    where warehouse = wh, date within (startDt; endDt)
 }

/ Day-over-day change
getDoD:{[dt]
  data:.cache.get[`wh_compare];
  dates:asc distinct data`date;
  prevDt:.dates.prev[dates; dt];
  if[null prevDt; :([] info:enlist "No previous date available")];
  .comparison.delta[data; `date; dt; prevDt; `warehouse; `total_value`total_units]
 }

/ Movement summary
getMovements:{[dt]
  select from .cache.get[`movements] where date = dt
 }

/ Category hierarchy drill-down
getCategoryTree:{[dt]
  select from .cache.get[`cat_hierarchy] where date = dt
 }

getCategoryChildren:{[dt; parentId]
  tree:select from .cache.get[`cat_hierarchy] where date = dt;
  .hierarchy.children[tree; parentId]
 }

/ Detail drill-down with filters
drillDown:{[dt; filters]
  data:select from .cache.get[`positions] where date = dt;
  if[not (::) ~ filters;
    data:.filters.apply[data; filters]];
  data
 }
