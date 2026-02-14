# kdb-infra

A lightweight, configuration-driven framework for managing analytical data pipelines in kdb+/q.

Built for teams running 10-20+ analytical applications off a shared partitioned database where data arrives as CSVs from multiple upstream systems. The framework handles ingestion, validation, orchestration, retention, and serving so that each application can focus on its own analytical logic.

## The Problem

Without shared infrastructure, each analytical application ends up with its own ingestion script, its own validation (or none), its own way of writing to the database, and its own definition of "clean data." Over time this leads to duplicated code, inconsistent data quality, and a database that becomes a dumping ground for data nobody fully understands.

## What This Framework Does

- **Validates before ingesting.** Every dataset has a schema. Data that doesn't conform gets rejected with a clear error, not silently loaded.
- **Enforces naming conventions.** Tables in the partitioned database must follow a `{domain}_{category}_{granularity}` pattern. No ad-hoc table names.
- **Orchestrates automatically.** A timer-based orchestrator scans for new files, checks dependencies across sources, and triggers the right application when all its data is ready.
- **Tracks everything.** An ingestion log records what was loaded, when, whether it succeeded or failed, and how many records. Persisted to the database so it survives restarts.
- **Archives processed files.** CSVs move from the landing zone to a dated archive after successful ingestion.
- **Manages retention.** Configurable policies prune old partitions — keep daily history for a year, monthly snapshots for two years, then purge.
- **Provides a shared library.** Common analytical operations — hierarchy flattening, rolling statistics, period comparisons, point-in-time joins, pivoting, filtering — available as stateless functions any app or server can use.
- **Supports server processes.** A cache framework lets server processes load tables from the database, apply transforms, hold results in memory, and refresh on a timer.
- **Supports dual environments.** Run prod and prod-parallel from the same codebase with different command line args.

## What This Framework Does Not Do

- **Application logic.** Each app owns its own transformations, aggregations, and serving strategy. The framework provides tools; the app decides what to do with them.
- **Frontend.** No UI components. This is backend data infrastructure only.
- **Real-time streaming.** Designed for batch/EOD analytical workloads where data arrives as files.

## Project Structure

```
kdb-infra/
├── core/
│   ├── validator.q           # Schema registry + validation rules
│   ├── csv_loader.q          # Load -> validate -> type cast
│   ├── ingestion_log.q       # Ingestion tracking, persisted to DB
│   └── db_writer.q           # Save to partitioned DB, enforce naming
├── orchestration/
│   └── orchestrator.q        # Timer loop, scanning, dependency check, dispatch
├── monitoring/
│   └── monitoring.q          # Failure alerts, staleness, disk health
├── maintenance/
│   └── retention_manager.q   # Partition cleanup per retention policy
├── lib/
│   ├── hierarchy.q           # Flatten hierarchical data
│   ├── rolling.q             # Windowed statistics (moving avg, std, etc.)
│   ├── filters.q             # Inclusion/exclusion filtering
│   ├── dates.q               # AsOf resolution, business days, date ranges
│   ├── comparison.q          # Period-over-period deltas and movers
│   ├── pivot.q               # Long <-> wide reshaping
│   └── temporal_join.q       # Point-in-time reference data joins
├── server/
│   ├── server_init.q         # Entry point for server processes
│   └── cache.q               # Recipe-based cache management
├── schemas/                   # One file per source/derived table
├── sources.q                  # Source -> app -> path -> pattern -> required
└── init.q                     # Entry point for orchestrator processes
```

## Two Entry Points

**Orchestrator** — ingests data, writes to the database:
```bash
q init.q -p 9000 -dbPath /data/databases/prod
```

**Server** — reads from the database, serves queries:
```bash
q server/server_init.q -p 9001 -dbPath /data/databases/prod
```

## Quick Start

**Orchestrator side:**
```q
.dbWriter.addDomain[`funding]
\l ../apps/funding/collateral/data_refresh.q
.orchestrator.registerApp[`funding_collateral; .funding.collateral.refresh]
.orchestrator.start[]
```

**Server side:**
```q
/ Register what to cache, how far back, and what transform to apply
.cache.register[`collateral_flat; `funding_collateral_source; 365;
  {[data] .hierarchy.flatten[data; `h_level1`h_level2`h_level3; `notional; enlist `date]}]

.cache.register[`collateral_by_ccy; `funding_collateral_by_currency; 90; ::]

.cache.loadAll[]
.cache.startRefresh[600000]

/ Query cached data
data:.cache.get[`collateral_by_ccy]
filtered:.filters.applyBoth[data; (enlist `currency)!(enlist `USD`EUR); ::]
```

## Shared Library

The `lib/` modules are stateless functions — table in, table out. Used by both data_refresh scripts and server processes.

| Module | Purpose |
|--------|---------|
| `hierarchy.q` | Flatten wide level columns to parent-child format |
| `rolling.q` | Moving average, std deviation, sum, min, max, median |
| `filters.q` | Apply inclusion filters and exclusions on any table |
| `dates.q` | AsOf/previous date resolution, business day logic |
| `comparison.q` | Period-over-period deltas, top movers, new/dropped entries |
| `pivot.q` | Reshape long to wide and wide to long |
| `temporal_join.q` | Point-in-time joins for time-varying reference data |

## Dual Environment

```bash
# Prod
q init.q -p 9000 -dbPath /data/databases/prod

# QA (leaner retention)
q init.q -p 8000 -dbPath /data/databases/prod_parallel -dailyRetention 90 -monthlyRetention 90
```

Same code, separate databases, independent orchestrators.

## Documentation

See [TECHNICAL.md](TECHNICAL.md) for detailed module documentation, the orchestrator flow, library API reference, cache patterns, and naming conventions.

## Requirements

- kdb+ 3.5+
- Linux (file operations and disk checks use standard Linux commands)

## License

MIT. See [LICENSE](LICENSE).
