# KDB+ Server Architecture & Data Flow

## Overview

The system has two separate q processes and one Vite dev server:

```
CSV Files → Orchestrator (port 9000) → HDB on disk
                                            ↓
                                    App Server (port 5010)
                                            ↓
                               Vite Dev Server (port 5173)
                                            ↓
                                    React Frontend
```

---

## 1. Ingestion — Orchestrator Process

**Started with:** `q init.q -p 9000 -dbPath C:/data/databases/prod_parallel -csvPath C:/data/csv`

### What it does

`init.q` loads the orchestrator framework and all app configs. When `.orchestrator.orchestratorRun[]` is called:

1. **Scans** the CSV directory for files matching registered patterns (e.g. `sales_transactions_*.csv`)
2. **Extracts the date** from the filename (`20240212` → `2024.02.12`)
3. **Checks the ingestion log** — skips files already processed
4. **Calls `.salesCore.refresh[date; sources]`** for each new file

### What `.salesCore.refresh` does (`apps/sales/core/data_refresh.q`)

```
CSV file
  → .csv.loadCSV[]          load raw transactions into memory
  → select ... by date, region  aggregate into sales_by_region
  → loop over distinct dates
      → .dbWriter.writeMultiple[]   write each date to its own partition
  → .dbWriter.reload[]      flush and reload the HDB
```

### HDB structure on disk

```
C:/data/databases/prod_parallel/
  2024.02.09/
    sales_transactions/   (raw rows)
    sales_by_region/      (aggregated: region, total_revenue, total_quantity)
  2024.02.12/
    sales_transactions/
    sales_by_region/
```

Each date is a separate directory partition. KDB+ uses these to enable efficient date-range queries via `select from table where date within (d1;d2)`.

---

## 2. App Server — Query Process

**Started with:** `q apps/sales/server.q -p 5010 -dbPath C:/data/databases/prod_parallel`

### Startup sequence (`server/server_init.q`)

```
server_init.q loads (in order):
  core/validator.q        schema validation helpers
  core/db_writer.q        sets HDB path, loads db into memory
  lib/catalog.q           field metadata system
  lib/dates.q             date navigation utilities
  lib/filters.q           filter/exclusion helpers
  lib/...                 other utility modules
  server/cache.q          in-memory table cache
  server/http.q           HTTP routing layer (.z.ph / .z.pp)
  server/cat_handlers.q   handlers for /catalog/* endpoints
  server/qry_handlers.q   handlers for /query/* endpoints
```

After loading, `apps/sales/server.q` runs:

```q
/ Load catalog from CSV (field metadata)
.catalog.load[catPath; `sales]

/ Register tables to cache with horizon
.cache.register[`sales_by_region; `sales_by_region; 9999; ::]

/ Register HTTP routes
.http.addRoute[`GET;  "/catalog/fields";        .catHandler.fields]
.http.addRoute[`GET;  "/catalog/filter-options"; .catHandler.filterOptions]
.http.addRoute[`POST; "/query/table";            .qryHandler.table]
.http.addRoute[`POST; "/query/trend";            .qryHandler.trend]

/ Load cache (reads from HDB into memory)
.cache.loadAll[]
```

### Cache (`server/cache.q`)

The cache reads partitioned tables from disk into memory once at startup, then serves all queries from RAM:

```
.cache.loadAll[]
  → .dbWriter.reload[]          refresh HDB connection
  → for each registered table:
      select from table where date >= (today - horizonDays)
      → store in .cache.cacheData dict
```

`sales_by_region` is registered with `horizonDays: 9999` so all history is loaded.

### HTTP Layer (`server/http.q`)

Routes are stored as a flat dict with compound symbol keys:

```
.http.routes:
  `GET/catalog/fields        → .catHandler.fields
  `GET/catalog/filter-options → .catHandler.filterOptions
  `POST/query/table          → .qryHandler.table
  `POST/query/trend          → .qryHandler.trend
```

**kdb+ 4.x calling convention:**
- `.z.ph[x]` is called for GET requests — `x` is a mixed list `(pathString; headerDict)`
- `.z.pp[x]` is called for POST requests — `x` is a mixed list `(bodyString; headerDict)`
- The path arrives **without** a leading slash (e.g. `"catalog/fields"`) — the handler prepends `/`
- POST routing uses a `_route` field embedded in the JSON body since kdb+ doesn't expose the URL path in `.z.pp`

---

## 3. Catalog System (`lib/catalog.q`)

The catalog drives what fields the frontend knows about. It's a CSV file:

```
config/catalog_sales.csv
  app, table, field, label, type, role, format, enabled
  sales, sales_by_region, region, Region, symbol, categorical, , 1
  sales, sales_by_region, total_revenue, Total Revenue, float, value, currency, 1
```

- **role = categorical** → appears as a dimension in FieldPicker (Region, Product)
- **role = value** → appears as a measure (Total Revenue, Total Quantity)
- **role = temporal** → date fields, not shown in FieldPicker

`.catalog.require[field; role]` validates that a query field exists and has the expected role — queries against unknown fields or wrong types are rejected with a clear error.

`.catalog.tableFor[field]` resolves which table to query for a given field — this is how the server knows `region` lives in `sales_by_region`.

---

## 4. Query Handlers (`server/qry_handlers.q`)

### `/query/table` — Day-over-Day Comparison

**Request:**
```json
{
  "field": "region",
  "measure": "total_revenue",
  "asofDate": "2024-02-12",
  "prevDate": "2024-02-09",
  "filters": { "region": ["AMER", "EMEA"] },
  "exclusions": {},
  "_route": "/query/table"
}
```

**Flow:**
```
1. Validate field/measure against catalog
2. Get table name from catalog (sales_by_region)
3. Load from cache
4. For each date (asof and prev):
   a. Filter to date partition: select from data where date = dt
   b. Apply include filters (keep only AMER, EMEA)
   c. Apply exclusions
   d. Aggregate: select sum(total_revenue) by region
   e. Return as dict: AMER->16500, EMEA->12150
5. Join asof and prev dicts, compute change and changePct per field value
6. Return list of dicts
```

**Response:**
```json
[
  { "region": "AMER", "asofValue": 18600, "prevValue": 16500, "change": 2100, "changePct": 0.127 },
  { "region": "EMEA", "asofValue": 13100, "prevValue": 11150, "change": 1950, "changePct": 0.175 }
]
```

### `/query/trend` — Time Series

**Request:**
```json
{
  "categoryField": "region",
  "measure": "total_revenue",
  "startDate": "2024-01-13",
  "endDate": "2024-02-12",
  "_route": "/query/trend"
}
```

**Flow:**
```
1. Validate against catalog
2. Load from cache
3. Filter to date window: select from data where date within (startDate; endDate)
4. Apply filters/exclusions
5. Aggregate by date × category: select sum(total_revenue) by date, region
6. Return list of dicts with ISO date strings
```

**Response:**
```json
[
  { "date": "2024-02-09", "category": "AMER", "value": 16500 },
  { "date": "2024-02-09", "category": "EMEA", "value": 12150 },
  { "date": "2024-02-12", "category": "AMER", "value": 18600 }
]
```

---

## 5. Frontend Integration

### Vite Proxy

The Vite dev server proxies all `/api/*` requests to `localhost:5010`, eliminating CORS:

```
Browser → localhost:5173/api/catalog/fields
         → (Vite proxy strips /api)
         → localhost:5010/catalog/fields
         → KDB+ response
         → Browser
```

This means the browser only ever talks to `localhost:5173` — no cross-origin requests.

### Startup Sequence in React (`pages/SalesView/index.tsx`)

```
1. Mount → getCatalogFields()
     GET /catalog/fields
     → FieldPicker populated with dimensions (Region, Product)
       and measures (Total Revenue, Total Quantity)

2. getCatalogFields resolves → getFilterOptions()
     GET /catalog/filter-options
     → Filter dropdown populated with AMER, EMEA, APAC etc.

3. User sets dates + measure + clicks Apply → getRegionSummaryFlat()
     POST /query/table  (for each enabled dimension)
     → Grid populated with DoD comparison rows

4. Chart toggle enabled → getTrendByDimension()
     POST /query/trend
     → Highcharts line chart rendered
```

### Service Layer (`pages/SalesView/salesService.ts`)

```typescript
getCatalogFields()    → GET  /catalog/fields
getFilterOptions()    → GET  /catalog/filter-options
getRegionSummaryFlat() → POST /query/table
getTrendByDimension()  → POST /query/trend
```

All POST requests embed `_route: endpoint` in the body so kdb+ can dispatch correctly.

---

## 6. Adding a New Domain/App

To add a new analytics domain (e.g. PnL), the pattern is:

1. **Create `apps/pnl/core/config.q`** — register sources, schemas, and `.pnl.refresh` function
2. **Create `apps/pnl/core/data_refresh.q`** — define `.pnl.refresh[dt; sources]`
3. **Add catalog rows to `config/catalog_pnl.csv`** — fields, roles, formats
4. **Create `apps/pnl/server.q`** — load server_init, load catalog, register cache entries and routes
5. **No changes to orchestrator** — it auto-discovers apps by walking `apps/*/`

The shared infrastructure (`lib/`, `server/`, `orchestration/`) is reused as-is.
