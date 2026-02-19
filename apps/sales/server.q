/ apps/sales/server.q
/ Sales domain server — serves data from the sales/core app
/ Start with: q apps/sales/server.q -p 5001 -dbPath /data/databases/prod

\l server/server_init.q

/ Load all sales app configs (registers schemas + domain)
loadDomainConfigs[`sales];

/ ============================================================================
/ CACHE RECIPES
/ ============================================================================

/ Transactions detail (90-day window)
.cache.register[`txns;       `sales_transactions; 90;  ::];

/ Regional aggregation (1-year window)
.cache.register[`by_region;  `sales_by_region;    365; ::];

/ Regional trend with rolling 30-day avg
.cache.register[`region_trend; `sales_by_region; 365;
  {[d] .rolling.addRolling[d; `total_revenue; 30; `avg; `revenue_30d_avg]}];

.cache.loadAll[]
.cache.startRefresh[600000]

/ ============================================================================
/ QUERY API
/ ============================================================================

/ Regional summary for a date
getByRegion:{[dt]
  select from .cache.get[`by_region] where date = dt
 }

/ Regional trend with rolling avg
getRegionTrend:{[rgn; startDt; endDt]
  select from .cache.get[`region_trend]
    where region = rgn, date within (startDt; endDt)
 }

/ Drill down to transaction detail
drillDown:{[dt; rgn]
  select from .cache.get[`txns] where date = dt, region = rgn
 }
