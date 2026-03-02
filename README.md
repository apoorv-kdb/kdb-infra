# KDB+ Analytics Infrastructure

A multi-application analytics platform built on KDB+/q. Designed to support financial analytical applications across domains — capital, margin, liquidity, PnL, funding — through shared ingestion infrastructure, a partitioned historical database, and reusable query primitives.

---

## Architecture in One Paragraph

CSV files land in a watched directory. An orchestrator process scans on a timer, validates files against a metadata catalog, transforms and aggregates the data, and writes partitions to a shared KDB+ historical database. Each application runs its own server process that loads from the shared database into an in-memory cache and exposes query functions to consuming frontends. A catalog CSV per application drives column mapping, type casting, validation, and field metadata — adding a new data source or accepting a new column alias requires only a catalog edit, no code changes.

For a full design walkthrough see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Prerequisites

- KDB+ 4.x (personal or commercial licence)
- Linux in production (see [docs/OPERATIONS.md](docs/OPERATIONS.md) for path changes from dev)
- Development was done on Windows — paths use `C:/data/` convention

---

## Directory Layout

```
kdb-infra/
├── orchestration/      Central ingestion loop
├── apps/sales/         Sales application (reference implementation)
├── core/               Shared ingestion infrastructure
├── lib/                Reusable analytical primitives
├── server/             Shared server infrastructure
├── config/             Catalog CSV files
└── docs/               Extended documentation
```

Data lives **outside** the code folder by design:

```
/data/
├── csv/                Drop CSV files here
└── databases/
    └── prod_parallel/  KDB+ partitioned database
```

---

## Quick Start

### 1. One-time setup

Create data directories:
```bash
mkdir -p /data/csv
mkdir -p /data/databases/prod_parallel
```

Copy seed CSV files:
```bash
cp data/csv/*.csv /data/csv/
```

### 2. Start the orchestrator

```bash
q orchestration/orchestrator.q -p 8000 -dbPath /data/databases/prod_parallel -csvPath /data/csv
```

On startup you should see:
```
Apps:    sales_core
Sources: 1
```

The orchestrator immediately runs its first scan. Watch for:
```
[OK] sales_core completed for 2026.01.27 (207 total rows)
```

### 3. Start the sales app server

In a new terminal:
```bash
q apps/sales/server.q -p 5010 -dbPath /data/databases/prod_parallel
```

You should see:
```
Cached sales_by_region: 207 rows
Sales server ready
```

---

## Adding a New Application

See [docs/EXTENDING.md](docs/EXTENDING.md) for the full step-by-step guide with a worked example.

The short version: write a catalog CSV, a `data_refresh.q`, a `config.q`, and a `server.q`. The orchestrator auto-discovers new apps — no changes to shared infrastructure needed.

---

## Key Operations

**Force reprocessing a date:**
```q
.orchestrator.resetSource[`sales_transactions; 2026.01.27]
```

**Check orchestrator status:**
```q
.orchestrator.status[]
```

**Manual refresh (without waiting for timer):**
```q
`.orchestrator.isRunning set 0b
.orchestrator.orchestratorRun[]
```

**Inspect cache:**
```q
.cache.get `sales_by_region
```

**Test a query handler directly:**
```q
.qryHandler.table[`field`measure`asofDate`prevDate`filters`exclusions!(
  "region"; "total_revenue"; "2026-02-24"; "2026-01-27"; ()!(); ()!())]
```

---

## Repository Layout Reference

| Path | Purpose |
|------|---------|
| `orchestration/orchestrator.q` | Timer-driven ingestion loop |
| `core/csv_loader.q` | Read CSV → typed table using catalog |
| `core/db_writer.q` | Write and reload HDB partitions |
| `core/ingestion_log.q` | Track processed source+date pairs |
| `lib/catalog.q` | Load catalog, rename, validate, cast |
| `lib/query.q` | Movement, spot, trend query handlers |
| `lib/cat_handlers.q` | Catalog query functions (fields, filter options) |
| `server/cache.q` | In-memory table cache with refresh timer |
| `server/server_init.q` | Shared server load sequence |
| `config/catalog_sales.csv` | Field definitions for sales app |
| `apps/sales/core/data_refresh.q` | Sales transform logic |
| `apps/sales/core/config.q` | Sales source registration |
| `apps/sales/server.q` | Sales server — cache + function exposure |

---

## Documentation

| Document | Contents |
|----------|---------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, data flow, design decisions |
| [docs/EXTENDING.md](docs/EXTENDING.md) | How to add a new application end-to-end |
| [docs/CATALOG.md](docs/CATALOG.md) | Catalog CSV column reference |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Linux porting, debugging, routine operations |
| [docs/QUERY_CONTRACT.md](docs/QUERY_CONTRACT.md) | Query handler integration reference |
