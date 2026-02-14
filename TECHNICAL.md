# Technical Documentation

## Architecture Overview

```
    CSV files land in /data/csv/
                |
                v

    ORCHESTRATOR (.z.ts)
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
    - Builds aggregations in native q (select...by, lj, etc.)
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
    │   └── infra_ingestion_log/         (persisted each tick)
    ├── 2024.02.13/
    └── sym
```

## Core Principle

The framework owns **getting clean data into the database with consistent structure**. Applications own **what to do with that data** — transformations, aggregations, joins, caching, and query serving.

---

## Module Reference

### core/validator.q

Central schema registry and validation rule library. Schemas registered here are used by both csv_loader (on load) and db_writer (on save).

#### Schema Registry

```q
/ Register a schema for a source or derived table
.validator.registerSchema[name; schema]

/ Look up a schema (returns (::) if not found)
.validator.getSchema[name]

/ Check if a schema exists
.validator.hasSchema[name]
```

Schema dict keys:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `columns` | symbol list | Yes | Expected column names |
| `types` | char list | Yes | kdb+ types aligned with columns (d, f, j, s, etc.) |
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

#### Custom Rules Example

```q
.validator.registerSchema[`my_source;
  `columns`types`mandatory`rules!(
    `date`amount`status;
    "dfs";
    `date`amount;
    enlist `name`fn`params!(
      "Amount must be positive";
      {[data; params] .validator.inRange[data; `amount; 0; 1e12]};
      ::)
  )
 ]
```

---

### core/csv_loader.q

Loads CSV files, validates against a registered schema, type casts all columns, and returns a clean typed table.

#### Functions

```q
/ Full load with explicit delimiter. Returns dict: success, data, error, recordCount
.csv.load[source; filepath; delimiter]

/ Load with default comma delimiter
.csv.loadDefault[source; filepath]

/ Load and return just the table. Throws on error.
.csv.loadStrict[source; filepath; delimiter]
```

#### Load Flow

1. Look up schema from `.validator.schemas`
2. Read raw CSV (all columns as strings/symbols)
3. Check mandatory columns exist in file
4. Keep only columns defined in schema (drop extras from CSV)
5. Validate raw data against schema
6. Type cast each column to target type
7. Return clean typed table

#### Return Value

```q
`success`data`error`recordCount!(1b; cleanTable; ""; 5000)
```

On failure, `success` is `0b` and `error` contains the reason.

---

### core/ingestion_log.q

In-memory table tracking every ingestion attempt. Persisted to the partitioned database at the end of each orchestrator tick. Reloaded on startup so state survives restarts.

#### Table Schema

| Column | Type | Description |
|--------|------|-------------|
| source | symbol | Source name from sources.q |
| date | date | Business date of the data |
| status | symbol | `processing`, `completed`, or `failed` |
| filepath | symbol | Path to the source file |
| recordCount | long | Records loaded (0 if failed) |
| errorMsg | string | Error description if failed |
| startTime | timestamp | When processing started |
| endTime | timestamp | When processing completed/failed |
| retryCount | int | Number of retry attempts |

#### Key Functions

```q
/ Lifecycle
.ingestionLog.init[]                            / Create empty table
.ingestionLog.reload[dbPath]                    / Reload from partitioned DB on startup
.ingestionLog.persist[]                         / Save to partitioned DB (end of tick)

/ Write operations
.ingestionLog.markProcessing[source; date; filepath]
.ingestionLog.markCompleted[source; date; recordCount]
.ingestionLog.markFailed[source; date; errorMsg]

/ Query operations
.ingestionLog.isProcessed[source; date]         / Boolean: completed?
.ingestionLog.allCompleted[sources; date]        / Boolean: all in list completed?
.ingestionLog.completedSources[date]             / Symbol list of completed sources
.ingestionLog.completedSince[timestamp]          / Sources completed since time (for archiving)
.ingestionLog.getStatus[source; date]            / Status for a source/date
.ingestionLog.getFailed[]                        / All failed entries
.ingestionLog.getByDate[date]                    / All entries for a date
.ingestionLog.getLatest[]                        / Most recent entry per source

/ Maintenance
.ingestionLog.purgeOld[days]                     / Remove entries older than N days
.ingestionLog.stats[]                            / Summary counts by source
```

#### Persistence

The ingestion log is saved to the partitioned database as `infra_ingestion_log`, partitioned by date like all other tables. This table is marked as protected in the retention manager so it is never pruned.

On startup, `init.q` calls `.ingestionLog.reload[dbPath]` to restore state. If no prior log exists, it falls back to an empty table.

---

### core/db_writer.q

Saves tables to the partitioned database. Two layers of governance:

1. **Naming convention** — table name must start with a registered domain followed by underscore
2. **Schema validation** — if a schema is registered for the table name, data is validated before writing

#### Functions

```q
/ Partitioned saves
.dbWriter.save[tableName; data; date]            / Save to date partition
.dbWriter.saveMultiple[tableMap; date]            / Save dict of tables at once

/ Non-partitioned saves
.dbWriter.saveFlat[tableName; data]               / Flat table in DB root

/ Domain management
.dbWriter.addDomain[domain]                       / Register allowed domain

/ Database operations
.dbWriter.reload[]                                / Reload DB after writes
.dbWriter.listPartitions[]                        / List all date partitions
.dbWriter.listTables[date]                        / List tables in a partition
.dbWriter.setDbPath[path]                         / Set database root
```

#### Naming Convention

Every table must follow: `{domain}_{category}_{granularity}`

The domain portion (everything before the first underscore) must be registered via `.dbWriter.addDomain`. Tables with unregistered domains are rejected.

Examples of valid names: `funding_collateral_source_agg`, `funding_collateral_detail`, `funding_collateral_by_currency`, `liquidity_cashflow_daily`.

#### Save Flow

1. Validate naming convention
2. Check data is a non-empty table
3. If schema exists for this table name, validate against it
4. Enumerate symbols against database sym file
5. Write to partition path: `dbPath/date/tableName/`

---

### orchestration/orchestrator.q

The central loop. Runs on `.z.ts` at a configurable interval (default 1 hour).

#### Orchestrator Tick — Step by Step

**1. Scan** — Reads the `source_config` table. Walks each directory and collects files matching the pattern. Extracts dates from filenames (supports YYYYMMDD, YYYY-MM-DD, YYYY_MM_DD, YYYY.MM.DD).

**2. Filter** — For each file found, queries `ingestion_log`. Keeps only new files and previously-failed files (for automatic retry).

**3. Group** — Clusters remaining work by app and date.

**4. Dependency check** — For each app/date, checks whether all required sources are available (found in this scan or previously completed per ingestion_log). If any required source is missing, that app/date is skipped.

**5. Dispatch** — Calls the app's registered `data_refresh` function with the business date and list of all available sources (required + optional).

**6. Persist ingestion_log** — Saves to the partitioned database so state survives restarts.

**7. Archive CSVs** — Moves successfully processed files to `archive/YYYY/MM/`. Only archives files completed during this tick.

**8. Monitor** — Calls monitoring.q to check for failures, stale sources, and system health.

#### App Registration

```q
.orchestrator.registerApp[`myapp; .myapp.refresh]
```

The refresh function must have signature `{[date; availableSources] ...}`.

#### Required vs Optional Sources

Sources in `source_config` have a `required` flag. Required sources must all be available before the orchestrator triggers that app. Optional sources are passed if present but not waited on.

```q
.myapp.refresh:{[dt; availableSources]
  main:.csv.loadStrict[`myapp_main; mainPath; ","];

  if[`myapp_supplemental in availableSources;
    extra:.csv.loadStrict[`myapp_supplemental; extraPath; ","]];
 }
```

#### Functions

```q
.orchestrator.registerApp[app; fn]
.orchestrator.start[]
.orchestrator.stop[]
.orchestrator.setInterval[ms]
.orchestrator.setArchivePath[path]
.orchestrator.run[]                               / Single run (no timer)
.orchestrator.manualRefresh[app; date]
.orchestrator.backfill[app; startDate; endDate]
.orchestrator.status[]
```

---

### monitoring/monitoring.q

Runs at the end of every orchestrator tick. Checks three things:

1. **Failures** — alerts on failed ingestions today
2. **Staleness** — alerts if daily sources haven't arrived within threshold (default 36 hours)
3. **Disk space** — alerts if available space below threshold (default 50 GB)

Alert function is pluggable:

```q
.monitoring.setAlertFn[{[severity; subject; body]
  payload:.j.j `text!("[",(string severity),"] ",subject,"\n",body);
  system "curl -X POST -d '",payload,"' https://hooks.slack.com/services/YOUR/WEBHOOK";
 }]
```

---

### maintenance/retention_manager.q

Enforces retention policy on partitions. Thresholds are configurable per environment.

#### Default Policy

| Age | Detailed tables | Aggregated tables | Protected tables |
|-----|----------------|-------------------|------------------|
| 0-1 year | Keep daily | Keep daily | Keep daily |
| 1-2 years | 1st of month only | Keep daily | Keep daily |
| 2+ years | Purge | Purge | Keep |

Protected tables (like `infra_ingestion_log`) are never purged.

#### Table Classification

```q
.retention.classify[`mydom_cat_detail; `detailed]
.retention.classify[`mydom_cat_by_business; `aggregated]

/ Or batch:
.retention.classifyBatch[
  `mydom_cat_detail`mydom_cat_by_business!`detailed`aggregated]
```

Unregistered tables default to `detailed`.

#### Functions

```q
.retention.setDailyRetention[days]
.retention.setMonthlyRetention[days]
.retention.classify[tableName; classification]
.retention.classifyBatch[tableMap]
.retention.run[asOfDate]
.retention.dryRun[asOfDate]
```

#### Dry Run

```q
q) .retention.dryRun[.z.d]
date       zone          action          detail
--------------------------------------------------------------
2024.02.12 zone1_recent  keep_all        Within daily retention
2023.01.15 zone2_monthly keep_all        Monthly snapshot - keep everything
2023.01.20 zone2_monthly prune_detailed  Remove detailed, keep aggregated
2021.06.01 zone3_old     purge           Beyond monthly retention
```

---

### sources.q

Configuration table. Edit to onboard new sources.

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

### schemas/*.q

One file per source or derived table. Each calls `.validator.registerSchema`.

Source schemas are required (csv_loader needs them). Derived table schemas are optional (db_writer validates if present).

See `schemas/example_source_agg.q` for the pattern.

---

### init.q

Single entry point. Accepts command line args for environment-specific configuration.

| Arg | Default | Description |
|-----|---------|-------------|
| `-dbPath` | `curated_db` | Partitioned database path |
| `-archivePath` | `/data/archive` | CSV archive directory |
| `-timerInterval` | `3600000` | Orchestrator interval (ms) |
| `-dailyRetention` | `365` | Days for daily partitions |
| `-monthlyRetention` | `730` | Days for monthly snapshots |

#### Load Order

1. `core/validator.q` — no dependencies
2. `core/ingestion_log.q` — no dependencies
3. `core/csv_loader.q` — depends on validator
4. `core/db_writer.q` — depends on validator
5. `sources.q` — configuration
6. `schemas/*.q` — all schema files
7. `monitoring/monitoring.q` — depends on core + config
8. `orchestration/orchestrator.q` — depends on core + config
9. `maintenance/retention_manager.q` — depends on db_writer

---

## Dual Environment Setup

Run two independent processes from the same code with different configuration.

**Production:**
```bash
q init.q -p 9000 -dbPath /data/databases/prod -archivePath /data/archive
```

**Production parallel (QA):**
```bash
q init.q -p 8000 -dbPath /data/databases/prod_parallel -archivePath /data/archive \
         -dailyRetention 90 -monthlyRetention 90
```

| Aspect | Prod | Prod Parallel |
|--------|------|---------------|
| Port | 9000 | 8000 |
| Database | /data/databases/prod | /data/databases/prod_parallel |
| Daily retention | 365 days | 90 days |
| Monthly retention | 730 days | 90 days |
| CSV source | Shared /data/csv/ | Shared /data/csv/ |
| Archive | Shared /data/archive/ | Shared /data/archive/ |
| Purpose | Serves users | Test changes before promotion |

Both processes scan the same CSV landing zone and ingest independently. Each has its own database and ingestion_log. No shared state.

---

## Application Pattern

### data_refresh.q

Called by the orchestrator. Uses framework tools for loading and saving, owns its own logic.

```q
\d .myapp

refresh:{[dt; availableSources]
  sourceAgg:.csv.loadStrict[`mydom_cat_source_agg; filepath; ","];
  detail:.csv.loadStrict[`mydom_cat_detail; filepath; ","];

  bizRef:("SSS"; enlist ",") 0: `:/data/ref/business_hierarchy.csv;

  byBusiness:select total:sum amount by date, business from detail;
  byProduct:select total:sum amount by date, product from detail;

  enriched:detail lj `business xkey bizRef;

  .dbWriter.save[`mydom_cat_source_agg; sourceAgg; dt];
  .dbWriter.save[`mydom_cat_detail; enriched; dt];
  .dbWriter.save[`mydom_cat_by_business; byBusiness; dt];
  .dbWriter.save[`mydom_cat_by_product; byProduct; dt];

  .dbWriter.reload[];
 }

\d .
```

### server.q

Runs as a separate process. Three-level cache pattern:

```q
\d .myapp

loadCache:{[]
  `.myapp.cache.trend set select from mydom_cat_source_agg where date > .z.d - 365;
  `.myapp.cache.byBusiness set select from mydom_cat_by_business where date > .z.d - 90;
 }

getTrend:{[] .myapp.cache.trend}
getByBusiness:{[startDt; endDt] select from .myapp.cache.byBusiness where date within (startDt; endDt)}
getDrillDown:{[dt; business] select from mydom_cat_detail where date=dt, business=business}

\d .
```

---

## Naming Convention

Every table must follow: `{domain}_{category}_{granularity}`

The domain must be registered with `.dbWriter.addDomain`.

---

## Retention Policy

Default thresholds (configurable per environment):

| Data age | Detailed tables | Aggregated tables | Protected tables |
|----------|----------------|-------------------|------------------|
| 0-1 year | Daily partitions | Daily partitions | Daily partitions |
| 1-2 years | 1st of month only | Daily partitions | Daily partitions |
| 2+ years | Purged | Purged | Kept |

---

## Onboarding

### New Source

1. Schema in `schemas/`: `.validator.registerSchema[`newsource; ...]`
2. Row in `sources.q`
3. Use in app's `data_refresh.q`

### New Application

1. Create `apps/newapp/data_refresh.q` with a refresh function
2. Create schema files for each source in `schemas/`
3. Add source rows to `sources.q`
4. Register domain: `.dbWriter.addDomain[`newdom]`
5. Register app: `.orchestrator.registerApp[`newapp; .newapp.refresh]`
6. Register retention classifications for each table
