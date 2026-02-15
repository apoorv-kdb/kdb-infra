/ sales domain — server.q
/ Single server for the sales domain, serving data from all sales apps
/ Start with: q apps/sales/server.q -p 5001 -dbPath /data/databases/prod

\l server/server_init.q

/ Load all sales app configs (registers schemas + domain)
loadDomainConfigs[`sales];

/ ============================================================================
/ CACHE RECIPES
/ ============================================================================

/ From core app: transactions detail + regional agg
.cache.register[`txns;       `sales_transactions; 90;  ::];
.cache.register[`by_region;  `sales_by_region;    365; ::];

/ From core app: regional trend with rolling 30-day avg
.cache.register[`region_trend; `sales_by_region; 365;
  {[d] .rolling.addRolling[d; `total_revenue; 30; `avg; `revenue_30d_avg]}];

/ From returns app: net revenue by region
.cache.register[`net_by_region; `sales_net_by_region; 365; ::];

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
getRegionTrend:{[region; startDt; endDt]
  select from .cache.get[`region_trend]
    where region = region, date within (startDt; endDt)
 }

/ Net revenue (after returns) by region
getNetByRegion:{[dt]
  select from .cache.get[`net_by_region] where date = dt
 }

/ Drill down to transaction detail
drillDown:{[dt; region]
  select from .cache.get[`txns] where date = dt, region = region
 }
