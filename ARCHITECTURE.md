# Architecture

## What This System Is

A multi-application analytics infrastructure built on KDB+/q, designed to support financial analytical applications across domains like capital, margin, liquidity, PnL, and funding. The system ingests CSV files, stores them in a partitioned historical database, and exposes reusable query functions that any frontend can consume.

The core architectural bet is that all applications share the same infrastructure — one ingestion pipeline, one database, one set of reusable query primitives — rather than each app owning its own silo. A metadata-driven catalog controls how each app sees and uses the shared data.

---

## System Overview

```
CSV files (/data/csv/)
        │
        ▼
  ┌─────────────┐
  │ Orchestrator│  port 8000
  │  (q process)│  scans, validates, ingests on timer
  └──────┬──────┘
         │ writes partitioned HDB
         ▼
  ┌─────────────────────────┐
  │  KDB+ Partitioned DB    │
  │  /data/databases/       │
  │  prod_parallel/         │
  │    2026.01.27/          │
  │      sales_transactions │
  │      sales_by_region    │
  │    2026.01.28/          │
  │      ...                │
  └──────┬──────────────────┘
         │ reads on startup + refresh timer
         ▼
  ┌─────────────┐
  │ App Server  │  port 5010 (sales), 5011 (next app), ...
  │  (q process)│  in-memory cache, exposes q functions
  └──────┬──────┘
         │ q function calls
         ▼
  ┌─────────────┐
  │  Frontend   │  consumes via framework connector
  │  (consumer) │
  └─────────────┘
```

---

## The Two-Process Design

KDB+ can only load **one partitioned database per process**. This is a hard constraint that shapes the entire architecture.

Each application gets its own server process pointing at a shared database. The orchestrator is a separate process that owns ingestion. They never communicate directly — the database on disk is the interface between them.

This means:
- Orchestrator writes → App server reads. No inter-process messaging.
- Multiple apps can run simultaneously on different ports.
- A failing app server doesn't affect ingestion, and vice versa.

---

## The Catalog-Driven Pattern

The catalog is the central innovation. It is a CSV file (`config/catalog_<app>.csv`) that describes every field an application cares about:

```
app,table,field,label,type,role,format,enabled,source_field
sales,sales_by_region,region,Region,symbol,categorical,,1,
sales,sales_by_region,total_revenue,Total Revenue,float,value,currency,1,
sales,sales_transactions,region,Region,symbol,categorical,,0,geo
sales,sales_transactions,region,Region,symbol,categorical,,0,region
sales,sales_transactions,region,Region,symbol,categorical,,0,GEO_REGION
```

The catalog drives four things without any code changes:

**1. Source field mapping** — the `source_field` column lists every accepted alias for a canonical field name. Multiple rows per field = multiple accepted aliases. This means messy CSVs from different systems (one calls it `geo`, another calls it `GEO_REGION`, another `region`) all map to the same canonical `region` field automatically.

**2. Type casting** — the `type` column tells the CSV loader how to cast each string column. `symbol`, `float`, `long`, `date`, `timestamp` are supported.

**3. Validation** — missing canonical columns are blocking (ingestion fails). Null counts are non-blocking (warnings only). Both are driven by the catalog, not hardcoded checks.

**4. Field metadata** — `enabled=1` fields are exposed via `.catHandler.fields` for frontends to consume. `enabled=0` fields are ingested and validated but hidden. This lets raw transaction tables be processed without surfacing them to consumers.

**The key insight:** adding a new data source or accepting a new column alias is a catalog CSV edit, not a code change.

---

## Data Flow: Ingestion

```
1. Orchestrator scans CSV directory on timer (default: 1 hour)
2. Extracts date from filename (expects YYYY-MM-DD, YYYY_MM_DD, or YYYYMMDD pattern)
3. Checks ingestion log — skips already-processed source+date combinations
4. For each unprocessed file:
   a. csv_loader.q reads all columns as strings
   b. catalog.q renames source columns to canonical names, drops unmapped columns
   c. catalog.q validates — blocking on missing columns, non-blocking on nulls
   d. catalog.q casts strings to typed columns
   e. data_refresh.q aggregates (e.g. transactions → by-region summaries)
   f. db_writer.q writes each partition to disk
   g. db_writer.q calls .Q.en to enumerate symbols
5. Ingestion log records completion for each source+date
6. App servers pick up new data on their next cache refresh (default: 10 minutes)
```

---

## Data Flow: Query

```
1. Frontend calls .qryHandler.table with {field, measure, asofDate, prevDate, filters, exclusions}
2. Handler reads from in-memory cache (e.g. sales_by_region)
3. Applies date filter (asofDate), then aggregates by field
4. Applies date filter (prevDate), then aggregates by field
5. Joins on field value, computes change and changePct
6. Returns table — one row per unique field value
```

The query layer never touches the partitioned database directly during serving — it reads from the in-memory cache loaded at startup. This keeps query latency low and isolates the serving layer from disk I/O.

---

## Directory Structure

```
kdb-infra/
├── orchestration/
│   └── orchestrator.q          Central ingestion loop
├── apps/
│   └── sales/
│       ├── core/
│       │   ├── data_refresh.q  Transform: raw → aggregated tables
│       │   └── config.q        Register sources + app with orchestrator
│       └── server.q            App server: cache + function exposure
├── core/                       Shared infrastructure
│   ├── csv_loader.q            Read CSV → typed table using catalog
│   ├── db_writer.q             Write partitions to HDB
│   └── ingestion_log.q         Track processed source+date pairs
├── lib/                        Reusable analytical primitives
│   ├── catalog.q               Load catalog, rename, validate, cast
│   ├── query.q                 Movement, spot, trend query handlers
│   ├── cat_handlers.q          Field and filter-option query functions
│   ├── filters.q               Include/exclude filter application
│   ├── dates.q                 Date arithmetic utilities
│   ├── comparison.q            Period-over-period delta (stub)
│   ├── hierarchy.q             Parent-child flattening (stub)
│   ├── rolling.q               Moving averages and windows (stub)
│   ├── pivot.q                 Long-to-wide reshaping (stub)
│   └── temporal_join.q         Point-in-time aj wrappers (stub)
├── server/                     Shared server infrastructure
│   ├── cache.q                 In-memory table cache with refresh timer
│   └── server_init.q           Load sequence for app servers
└── config/
    └── catalog_sales.csv       Field definitions for sales app
```

---

## The Ingestion Log

The ingestion log prevents double-processing. Every source+date combination is recorded with status (`processing`, `completed`, `failed`), row count, and any warnings. It is persisted to the HDB as `infra_ingestion_log` partitions, so it survives orchestrator restarts.

To force reprocessing of a specific source+date:
```q
.orchestrator.resetSource[`sales_transactions; 2026.01.27]
```

---

## Analytical Modes

Three query handlers are exposed per app server:

**Movement** (`.qryHandler.table`) — compares two dates. Returns one row per unique field value with asof value, prev value, absolute change, and change %. Requires `field`, `measure`, `asofDate`, `prevDate`.

**Spot** (`.qryHandler.spot`) — single date snapshot. Returns absolute value and composition percentage. Requires `field`, `measure`, `asofDate`.

**Trend** (`.qryHandler.trend`) — time series over a window. Returns a date × category matrix. Requires `categoryField`, `measure`, `startDate`, `endDate`.

Two catalog functions are also exposed:

- `.catHandler.fields` — returns enabled fields with labels, types, and formats
- `.catHandler.filterOptions` — returns all categorical field values for filter UI population

---

## What Is Not Yet Built

Several `lib/` modules exist as documented stubs:

- `comparison.q` — period-over-period deltas
- `hierarchy.q` — flatten wide hierarchies to parent-child for drill-down
- `rolling.q` — moving averages and rolling sums
- `pivot.q` — long-to-wide reshaping for cross-tab views
- `temporal_join.q` — point-in-time `aj` for time-varying reference data

These are the natural next extensions once the core pipeline is validated.
