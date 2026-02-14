# kdb-infra

A lightweight, configuration-driven framework for managing analytical data pipelines in kdb+/q.

Built for teams running 10-20+ analytical dashboards off a shared partitioned database where data arrives as CSVs from multiple upstream systems. The framework handles ingestion, validation, orchestration, and retention so that each application can focus on its own analytical logic.

## The Problem

Without shared infrastructure, each analytical application ends up with its own ingestion script, its own validation (or none), its own way of writing to the database, and its own definition of "clean data." Over time this leads to duplicated code, inconsistent data quality, and a database that becomes a dumping ground for data nobody fully understands.

## What This Framework Does

- **Validates before ingesting.** Every dataset has a schema. Data that doesn't conform gets rejected with a clear error, not silently loaded.
- **Enforces naming conventions.** Tables in the partitioned database must follow a `{domain}_{category}_{granularity}` pattern. No ad-hoc table names.
- **Orchestrates automatically.** A timer-based orchestrator scans for new files, checks dependencies across sources, and triggers the right application when all its data is ready.
- **Tracks everything.** An ingestion log records what was loaded, when, whether it succeeded or failed, and how many records. Persisted to the database so it survives restarts.
- **Archives processed files.** CSVs move from the landing zone to a dated archive after successful ingestion.
- **Manages retention.** Configurable policies prune old partitions — keep daily history for a year, monthly snapshots for two years, then purge.
- **Supports dual environments.** Run prod and prod-parallel from the same codebase with different command line args. Test changes against real data before promoting.

## What This Framework Does Not Do

- **Application logic.** Each app owns its own transformations, aggregations, joins, and caching strategy. The framework provides tools (csv_loader, db_writer, validator); the app decides what to do with them.
- **Frontend.** No UI components. This is backend data infrastructure only.
- **Real-time streaming.** Designed for batch/EOD analytical workloads where data arrives as files.

## Project Structure

```
infrastructure/
├── core/
│   ├── validator.q           # Schema registry + validation rules
│   ├── csv_loader.q          # Load → validate → type cast
│   ├── ingestion_log.q       # Ingestion tracking, persisted to DB
│   └── db_writer.q           # Save to partitioned DB, enforce naming
├── orchestration/
│   └── orchestrator.q        # Timer loop, scanning, dependency check, dispatch
├── monitoring/
│   └── monitoring.q          # Failure alerts, staleness, disk health
├── maintenance/
│   └── retention_manager.q   # Partition cleanup per retention policy
├── schemas/                   # One file per source/derived table
├── sources.q                  # Source → app → path → pattern → required
└── init.q                     # Entry point, loads everything
```

Each application lives outside the framework:

```
apps/
└── myapp/
    ├── data_refresh.q        # What to load, transform, save
    └── server.q              # Hot cache, query endpoints
```

## Quick Start

```bash
cd infrastructure
q init.q -p 9000 -dbPath /data/databases/prod
```

```q
/ Register your domain and app
.dbWriter.addDomain[`mydom]
\l ../apps/myapp/data_refresh.q
.orchestrator.registerApp[`myapp; .myapp.refresh]

/ Start
.orchestrator.start[]
```

## Onboarding a New Source

1. Define a schema in `schemas/`:
   ```q
   .validator.registerSchema[`newsource;
     `columns`types`mandatory!(`date`business`amount; "dsf"; `date`amount)]
   ```

2. Add a row to `sources.q`:
   ```q
   `source_config insert (`newsource; `myapp; 1b; `:/data/csv; "newsource_*.csv"; ","; `daily)
   ```

3. Use it in your app's `data_refresh.q`:
   ```q
   data:.csv.loadStrict[`newsource; filepath; ","]
   ```

No framework code changes needed.

## Dual Environment

Run prod and QA side by side against the same raw data:

```bash
# Prod
q init.q -p 9000 -dbPath /data/databases/prod

# QA (leaner retention)
q init.q -p 8000 -dbPath /data/databases/prod_parallel -dailyRetention 90 -monthlyRetention 90
```

Same code, separate databases, independent orchestrators.

## Documentation

See [TECHNICAL.md](TECHNICAL.md) for detailed module documentation, the orchestrator flow, application patterns, retention policy, and naming conventions.

## Requirements

- kdb+ 3.5+
- Linux (file operations and disk checks use standard Linux commands)

## License

MIT. See [LICENSE](LICENSE).
