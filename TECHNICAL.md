# Technical Documentation

## Architecture Overview

```
    CSV files land in /data/csv/
                |
                v

    ORCHESTRATOR PROCESS (init.q)
    =========================================
    1. Scan        - walk directories in sources.q, match file patterns
    2. Filter      - check ingestion_log, keep only new/retry files
    3. Group       - cluster new files by app and date
    4. Dependency  - are all required sources ready for this app?
    5. Dispatch    - call app's data_refresh function
    6. Persist     - save ingestion_log to partitioned DB
    7. Archive     - move processed CSVs to archive/YYYY/MM/
    8. Monitor     - check for failures, stale sources, disk health

                |
                |  For each app/date with dependencies met:
                v

    APP data_refresh.q
    =========================================
    - Loads its sources via csv_loader (validate + type cast)
    - Loads any reference data it needs
    - Builds aggregations in native q
    - Saves all tables via db_writer (naming enforced)

                |
                v

    PARTITIONED DATABASE
    =========================================
    curated_db/
    ├── 2024.02.12/
    │   ├── domain1_cat1_source_agg/
    │   ├── domain1_cat1_detail/
    │   ├── domain1_cat1_by_business/
    │   └── infra_ingestion_log/
    ├── 2024.02.13/
    └── sym

                |
                v

    SERVER PROCESSES (server/server_init.q)
    =========================================
    - Load tables from DB with configurable horizons
    - Transform using lib/ functions (flatten, rolling, etc.)
    - Hold in memory as hot cache
    - Refresh on timer
    - Serve queries to dashboards and consumers
```

## Core Principle

The framework has three layers. The **orchestrator** owns getting clean data into the database with consistent structure. **Applications** own what to transform and save. **Servers** own how to shape and serve that data to consumers, using **lib/** as shared building blocks.

---

## Module Reference: core/

### core/validator.q

Central schema registry and validation rule library.

#### Schema Registry

```q
.validator.registerSchema[name; schema]    / Register a schema
.validator.getSchema[name]                  / Look up (returns (::) if not found)
.validator.hasSchema[name]                  / Check if exists
```

Schema dict keys:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `columns` | symbol list | Yes | Expected column names |
| `types` | char list | Yes | kdb+ types aligned with columns |
| `mandatory` | symbol list | Yes | Columns that cannot contain nulls |
| `rules` | list of dicts | No | Custom validation rules |

#### Validation Rules

```q
.validator.notNull[data; col]                   / No nulls
.validator.typeCheck[data; col; expectedType]    / Can cast to type
.validator.inSet[data; col; allowedValues]       / Value in set
.validator.inRange[data; col; min; max]          / Numeric range
.validator.unique[data; keyCols]                 / Uniqueness
.validator.rowCount[data; minRows; maxRows]      / Row count range
.validator.validateSchema[data; schema]          / Full schema validation
```

Each rule returns a dict with `pass` (boolean) and `failures` (list of row indices that failed).

---

### core/csv_loader.q

Loads CSV files, validates against a registered schema, type casts all columns.

```q
.csv.load[source; filepath; delimiter]        / Full load, returns dict
.csv.loadDefault[source; filepath]             / Comma delimiter
.csv.loadStrict[source; filepath; delimiter]   / Returns table or throws
```

---

### core/ingestion_log.q

In-memory table tracking every ingestion attempt. Persisted to the partitioned database at the end of each orchestrator tick. Reloaded on startup.

| Column | Type | Description |
|--------|------|-------------|
| source | symbol | Source name from sources.q |
| date | date | Business date |
| status | symbol | `processing`, `completed`, or `failed` |
| filepath | symbol | Path to source file |
| recordCount | long | Records loaded |
| errorMsg | string | Error description if failed |
| startTime | timestamp | When processing started |
| endTime | timestamp | When completed/failed |
| retryCount | int | Retry attempts |

```q
/ Lifecycle
.ingestionLog.init[]                        / Create empty table
.ingestionLog.reload[dbPath]                / Reload from DB on startup
.ingestionLog.persist[]                     / Save to DB (end of tick)

/ Write
.ingestionLog.markProcessing[source; date; filepath]
.ingestionLog.markCompleted[source; date; recordCount]
.ingestionLog.markFailed[source; date; errorMsg]

/ Query
.ingestionLog.isProcessed[source; date]
.ingestionLog.allCompleted[sources; date]
.ingestionLog.completedSources[date]
.ingestionLog.completedSince[timestamp]
.ingestionLog.getLatest[]
```

---

### core/db_writer.q

Saves tables to the partitioned database. Enforces naming convention and optional schema validation.

```q
.dbWriter.addDomain[domain]                  / Register allowed domain
.dbWriter.save[tableName; data; date]        / Save to date partition
.dbWriter.saveFlat[tableName; data]          / Save non-partitioned
.dbWriter.saveMultiple[tableMap; date]       / Save multiple tables
.dbWriter.reload[]                           / Reload database
.dbWriter.setDbPath[path]                    / Set database root
```

Table names must follow `{domain}_{...}`. Domain must be registered via `addDomain`.

---

## Module Reference: orchestration/

### orchestration/orchestrator.q

Timer-based loop. Runs on `.z.ts` at a configurable interval.

#### Each Tick

1. **Scan** — walk directories in `source_config`, match file patterns, extract dates
2. **Filter** — check ingestion_log, keep new and retry files
3. **Group** — cluster by app and date
4. **Dependency check** — all required sources available?
5. **Dispatch** — call app's registered data_refresh function
6. **Persist** — save ingestion_log to DB
7. **Archive** — move processed CSVs to `archive/YYYY/MM/`
8. **Monitor** — check failures, staleness, disk health

```q
.orchestrator.registerApp[app; fn]           / Register app refresh function
.orchestrator.start[]                         / Start timer
.orchestrator.stop[]                          / Stop timer
.orchestrator.run[]                           / Single manual run
.orchestrator.manualRefresh[app; date]        / Force specific app/date
.orchestrator.backfill[app; start; end]       / Run for date range
```

---

## Module Reference: monitoring/

### monitoring/monitoring.q

Runs at the end of every orchestrator tick.

1. **Failures** — alerts on failed ingestions today
2. **Staleness** — alerts if daily sources haven't arrived within threshold (default 36 hours)
3. **Disk space** — alerts if available space below threshold (default 50 GB)

Alert function is pluggable via `.monitoring.setAlertFn`.

---

## Module Reference: maintenance/

### maintenance/retention_manager.q

Enforces retention policy. Thresholds configurable per environment.

| Age | Detailed tables | Aggregated tables | Protected tables |
|-----|----------------|-------------------|------------------|
| 0-1 year | Keep daily | Keep daily | Keep daily |
| 1-2 years | 1st of month only | Keep daily | Keep daily |
| 2+ years | Purge | Purge | Keep |

```q
.retention.setDailyRetention[days]
.retention.setMonthlyRetention[days]
.retention.classify[tableName; classification]
.retention.run[asOfDate]
.retention.dryRun[asOfDate]
```

---

## Module Reference: lib/

All lib modules are stateless — table in, table out. No dependencies on each other or on the rest of the infrastructure. Used by data_refresh scripts and server processes alike.

### lib/hierarchy.q

Flatten wide hierarchical data into parent-child format.

Input shape: `date, h_level1, h_level2, h_level3, ..., metrics`
Output shape: `date, h_name, h_id, h_pid, h_depth, metrics`

IDs are built by concatenating level values with `|` as separator. Metrics are aggregated at each level.

```q
/ Flatten wide levels to parent-child
/ Args: data, levelCols (symbol list), metricCols (symbol list), dateCols (symbol list or ::)
.hierarchy.flatten[data; `h_level1`h_level2`h_level3; `notional`count; enlist `date]

/ Navigate the flattened hierarchy
.hierarchy.children[data; parentId]          / Direct children of a node
.hierarchy.descendants[data; parentId]       / All descendants (recursive)
.hierarchy.path[data; id]                    / Path from root to a node
.hierarchy.roots[data]                       / Root nodes (h_pid = `)
.hierarchy.leaves[data]                      / Leaf nodes (not a parent of anything)
.hierarchy.atDepth[data; depth]              / All nodes at a given depth

/ Custom grouping
.hierarchy.addCustomGroup[data; mapping]     / Add h_custom via mapping table
.hierarchy.aggregateByCustom[data; metricCols; dateCols]  / Aggregate to custom level
```

---

### lib/rolling.q

Windowed statistics over time series data.

```q
/ Add a single rolling statistic
/ fn: one of `avg`sum`std`min`max`median
.rolling.addRolling[data; `notional; 30; `avg; `notional_30d_avg]

/ Add multiple rolling statistics at once
.rolling.addMultiple[data; specs]

/ Grouped rolling (e.g. per business)
.rolling.addRollingBy[data; `business; `notional; 30; `avg; `notional_30d_avg]

/ Convenience: generate standard specs (avg, std, min, max) for a column + window
specs:.rolling.standardSpecs[`notional; 30]
/ Returns 4 spec dicts: notional_30d_avg, notional_30d_std, notional_30d_min, notional_30d_max
```

Core window functions are also available directly:

```q
.rolling.avg[vals; window]
.rolling.movSum[vals; window]
.rolling.movStd[vals; window]
.rolling.movMin[vals; window]
.rolling.movMax[vals; window]
.rolling.movMedian[vals; window]
```

---

### lib/filters.q

Apply inclusion filters and exclusions to any table.

```q
/ Inclusion filters - keep rows matching column values
.filters.apply[data; `currency`business!(`USD`EUR; enlist `Trading)]

/ Exclusion filters - remove rows matching column values
.filters.exclude[data; (enlist `product)!(enlist `Repo)]

/ Both in one call (filters first, then exclusions)
.filters.applyBoth[data; filters; exclusions]

/ Column filtering
.filters.selectCols[data; `date`business`notional]
.filters.dropCols[data; `internal_id`debug_flag]

/ Date filtering
.filters.dateRange[data; 2024.01.01; 2024.12.31]
.filters.lastNDays[data; 90]
.filters.month[data; 2024; 6]

/ Conditional
.filters.inRange[data; `notional; 0; 1e9]
.filters.notNull[data; `currency]
.filters.matching[data; `business; "*Trading*"]
```

Pass `(::)` for filters or exclusions when you want none.

---

### lib/dates.q

Date resolution, business day logic, and date range generation.

#### AsOf Resolution

```q
dates:.dates.fromTable[data]                / Extract sorted distinct dates from a table
.dates.asOf[dates; 2024.12.15]              / Max date <= target
.dates.prev[dates; 2024.12.13]              / Max date < target
.dates.next[dates; 2024.12.13]              / Min date > target
.dates.asOfPair[dates; 2024.12.15]          / Returns `current`previous dict
```

#### Business Days

```q
.dates.setHolidays[holidayDateList]          / Set holiday calendar
.dates.loadHolidays["/path/to/holidays.csv"] / Load from file

.dates.isBizDay[2024.12.25]                 / Is it a business day?
.dates.nextBizDay[2024.12.25]               / Next biz day on or after
.dates.prevBizDay[2024.12.25]               / Prev biz day on or before
.dates.nextBizDayAfter[2024.12.13]          / Next biz day strictly after
.dates.prevBizDayBefore[2024.12.13]         / Prev biz day strictly before
.dates.nBizDaysBack[.z.d; 10]              / 10 business days ago
.dates.nBizDaysForward[.z.d; 5]            / 5 business days ahead
.dates.bizDaysBetween[start; end]            / Count business days in range
.dates.bizDayRange[start; end]               / List business days in range
```

#### Date Ranges

```q
.dates.monthEnds[2024.01.01; 2024.12.31]    / Month-end dates
.dates.monthStarts[2024.01.01; 2024.12.31]  / Month-start dates
.dates.quarterEnds[2024.01.01; 2024.12.31]  / Quarter-end dates
.dates.eom[2024.06.15]                      / End of month: 2024.06.30
.dates.som[2024.06.15]                      / Start of month: 2024.06.01
```

---

### lib/comparison.q

Period-over-period deltas and change analysis.

```q
/ Core delta: compare current vs previous on matching keys
/ Returns table with: keyCols + metric, metric_prev, metric_chg, metric_pct
.comparison.delta[current; previous; keyCols; metricCols]

/ Shortcut: same table, two dates
.comparison.deltaByDate[data; 2024.12.13; 2024.12.12; `business`product; `notional]

/ Aggregate comparison (totals only)
.comparison.totalDelta[current; previous; metricCols]

/ Find biggest changes
.comparison.topMovers[deltaTable; `notional; 10]

/ Find new and dropped entries between periods
.comparison.newEntries[current; previous; keyCols]
.comparison.droppedEntries[current; previous; keyCols]
```

---

### lib/pivot.q

Reshape tables between long and wide formats.

```q
/ Long to wide
/ Each distinct value in pivotCol becomes a new column
.pivot.toWide[data; enlist `date; `currency; `notional; sum]
.pivot.sumWide[data; enlist `date; `currency; `notional]  / sum shortcut

/ Wide to long
.pivot.toLong[data; `date`business; `USD`EUR`GBP; `currency; `notional]
.pivot.melt[data; `date`business; `currency; `notional]   / auto-detect value cols

/ Cross-tabulation (two-way pivot)
.pivot.crossTab[data; `business; `currency; `notional; sum]

/ Fill nulls in pivoted data
.pivot.fillZero[data; `USD`EUR`GBP]
.pivot.fillNulls[data; 0f; `USD`EUR`GBP]
```

---

### lib/temporal_join.q

Point-in-time joins for time-varying reference data. When reference data (credit ratings, fundability scores, business hierarchies) changes over time, these functions join the correct historical value based on the fact table's business date.

```q
/ AsOf join: attach reference data as of fact date
/ For each fact row, finds latest ref row where refDate <= factDate and keys match
.tj.asOfJoin[fact; ref; keyCols; factDateCol; refDateCol; valueCols]

/ Simplified: both tables use `date, bring all non-key columns
.tj.asOfJoinSimple[fact; ref; keyCols]

/ Window join: aggregate reference data within a lookback window
.tj.windowJoin[fact; ref; keyCols; factDateCol; refDateCol; windowDays; aggSpecs]

/ Reference data utilities
.tj.latest[ref; keyCols; dateCol]            / Latest value per key
.tj.snapshot[ref; keyCols; dateCol; asOfDate] / Values as of a specific date
.tj.history[ref; keyCols; keyVals; dateCol]   / Full change history for a key
```

---

## Module Reference: server/

### server/server_init.q

Entry point for server processes. Loads the minimal infrastructure needed for serving: validator, db_writer, all schemas, all lib modules, and cache.

Does **not** load: orchestrator, monitoring, retention, ingestion_log, sources.

```bash
q server/server_init.q -p 9001 -dbPath /data/databases/prod
```

| Arg | Default | Description |
|-----|---------|-------------|
| `-dbPath` | `curated_db` | Partitioned database path |

After loading, register cache entries and start serving.

---

### server/cache.q

Recipe-based cache management. Each cached table is a "recipe" — a table name, a date horizon, and an optional transform function. On refresh, all recipes are replayed from the database.

```q
/ Register a recipe
/ transformFn: {[data] ...} or (::) for no transform
.cache.register[`name; `tableName; horizonDays; transformFn]

/ Load all registered recipes from DB into memory
.cache.loadAll[]

/ Access cached data
.cache.get[`name]                            / Returns cached table
.cache.has[`name]                            / Check if cached
.cache.list[]                                / All entries with metadata and row counts

/ Refresh (reload from DB, re-apply transforms)
.cache.refresh[]
.cache.startRefresh[600000]                  / Timer-based refresh (ms)
.cache.stopRefresh[]

/ On-demand queries for uncached tables (drill-down)
.cache.drillDown[`detail_table; asOfDate]
/ Returns dict: `current`previous`currentDate`previousDate

/ Remove a recipe
.cache.remove[`name]
```

#### Cache + Lib Example

A server that flattens a hierarchy, adds rolling averages, and caches the result:

```q
\l server/server_init.q

.cache.register[`collateral; `funding_collateral_source; 365;
  {[data]
    flat:.hierarchy.flatten[data; `h_level1`h_level2`h_level3; `notional; enlist `date];
    .rolling.addRolling[flat; `notional; 30; `avg; `notional_30d_avg]
  }]

.cache.loadAll[]
.cache.startRefresh[600000]
```

Consumers query through server-defined endpoints that use `.cache.get` and `.filters.applyBoth` internally.

---

## Configuration: sources.q

| Column | Type | Description |
|--------|------|-------------|
| source | symbol | Unique name (must match schema registration) |
| app | symbol | Owning application |
| required | boolean | Must arrive before app runs? |
| directory | symbol | Landing directory |
| filePattern | string | Glob pattern |
| delimiter | char | CSV delimiter |
| frequency | symbol | `daily`, `weekly`, `monthly` |

---

## Configuration: schemas/*.q

One file per source or derived table. Each calls `.validator.registerSchema`. Source schemas are required (csv_loader needs them). Derived table schemas are optional (db_writer validates if present).

---

## Entry Points

### init.q (Orchestrator)

| Arg | Default | Description |
|-----|---------|-------------|
| `-dbPath` | `curated_db` | Partitioned database path |
| `-archivePath` | `/data/archive` | CSV archive directory |
| `-timerInterval` | `3600000` | Orchestrator interval (ms) |
| `-dailyRetention` | `365` | Days for daily partitions |
| `-monthlyRetention` | `730` | Days for monthly snapshots |

Loads: core/, orchestration/, monitoring/, maintenance/, sources.q, schemas/

### server/server_init.q (Server)

| Arg | Default | Description |
|-----|---------|-------------|
| `-dbPath` | `curated_db` | Partitioned database path |

Loads: core/validator.q, core/db_writer.q, schemas/, lib/, server/cache.q

---

## Dual Environment Setup

```bash
# Prod orchestrator
q init.q -p 9000 -dbPath /data/databases/prod

# QA orchestrator
q init.q -p 8000 -dbPath /data/databases/prod_parallel -dailyRetention 90 -monthlyRetention 90

# Servers point to whichever database they need
q server/server_init.q -p 9001 -dbPath /data/databases/prod
q server/server_init.q -p 8001 -dbPath /data/databases/prod_parallel
```

| Aspect | Prod | Prod Parallel |
|--------|------|---------------|
| Orchestrator port | 9000 | 8000 |
| Database | /data/databases/prod | /data/databases/prod_parallel |
| Daily retention | 365 days | 90 days |
| CSV source | Shared /data/csv/ | Shared /data/csv/ |

---

## Naming Convention

Every table must follow: `{domain}_{...}`

The domain must be registered with `.dbWriter.addDomain`.

---

## Application Pattern

### data_refresh.q

Called by the orchestrator. Uses framework tools for loading and saving, owns its own logic. Can use lib/ functions if it needs to persist transformed data.

```q
\d .myapp

refresh:{[dt; availableSources]
  / Load via framework
  sourceAgg:.csv.loadStrict[`mydom_cat_source_agg; filepath; ","];
  detail:.csv.loadStrict[`mydom_cat_detail; filepath; ","];

  / Transform (app-specific logic)
  byBusiness:select total:sum amount by date, business from detail;

  / Save via framework
  .dbWriter.save[`mydom_cat_source_agg; sourceAgg; dt];
  .dbWriter.save[`mydom_cat_detail; detail; dt];
  .dbWriter.save[`mydom_cat_by_business; byBusiness; dt];
  .dbWriter.reload[];
 }

\d .
```

### Server

Each server is its own q process. No fixed structure — each one is user-written code that loads `server_init.q` and uses cache + lib however it needs to.

```q
\l server/server_init.q

/ Build cache
.cache.register[`by_business; `mydom_cat_by_business; 365; ::]
.cache.register[`by_business_rolling; `mydom_cat_by_business; 400;
  {[data] .rolling.addRolling[data; `total; 30; `avg; `total_30d_avg]}]
.cache.loadAll[]
.cache.startRefresh[600000]

/ Define query endpoints
getTrend:{[] .cache.get[`by_business]}
getSlice:{[filters; exclusions]
  .filters.applyBoth[.cache.get[`by_business]; filters; exclusions]}
getDrillDown:{[asOfDate]
  .cache.drillDown[`mydom_cat_detail; asOfDate]}
```

Servers are per use-case, not per domain. A server can pull from any domain's tables.

---

## Cross-Domain Data

Apps and servers can read any table from the database regardless of domain. The database is the shared contract. No orchestrator coordination needed for cross-domain reads.

---

## Onboarding

### New Source

1. Schema in `schemas/`
2. Row in `sources.q`
3. Use in app's `data_refresh.q`

### New Application

1. Create `data_refresh.q` with a refresh function
2. Create schema files for each source
3. Add source rows to `sources.q`
4. Register domain: `.dbWriter.addDomain[`newdom]`
5. Register app: `.orchestrator.registerApp[`newapp; .newapp.refresh]`
6. Register retention classifications for each table

### New Server

1. Create a q script that loads `server/server_init.q`
2. Register cache entries with `.cache.register`
3. Call `.cache.loadAll[]` and `.cache.startRefresh[ms]`
4. Define query endpoints as functions
