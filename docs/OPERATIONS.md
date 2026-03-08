# Operations Reference
*Personal reference — running, debugging, and porting the system*

---

## Linux Porting

### 1. ROOT Resolution — 3 Files

The Windows ROOT line replaces backslashes. Remove the `ssr` call on Linux.

**Windows (current):**
```q
ROOT:rtrim ssr[{$[10h=type x;x;first x]} system "cd"; "\\"; "/"]
```

**Linux:**
```q
ROOT:rtrim {$[10h=type x;x;first x]} system "cd"
```

Files to change:

| File | Location |
|------|----------|
| `orchestration/orchestrator.q` | STARTUP block |
| `server/server_init.q` | Line 6 |
| `apps/sales/server.q` | Line 5 |
| `apps/<new_app>/server.q` | Line 5 (each new app) |

---

### 2. Default Data Paths — 4 Files

These defaults are only used when paths are not passed on the command line. In production always pass `-dbPath` and `-csvPath` explicitly. Still worth updating to avoid confusion.

| File | What | Current default | Change to |
|------|------|----------------|-----------|
| `core/db_writer.q` | `.dbWriter.dbPath` initial value | `` `:C:/data/databases/prod_parallel `` | `` `:/your/db/path `` |
| `orchestration/orchestrator.q` | `argDbPath` | `"C:/data/databases/prod_parallel"` | `"/your/db/path"` |
| `orchestration/orchestrator.q` | `argCsvPath` | `"C:/data/csv"` | `"/your/csv/path"` |
| `server/server_init.q` | `argDbPath` | `` `$"C:/data/databases/prod_parallel" `` | `` `$"/your/db/path" `` |

Note: `apps/sales/core/config.q` is gone — `csvDir` is now resolved by the orchestrator from `argCsvPath` and passed to `lib/discovery.q` at runtime. No per-app default to update.

---

### 3. Startup Commands

```bash
# Windows
q orchestration\orchestrator.q -p 8000 -dbPath C:/data/databases/prod_parallel -csvPath C:/data/csv
q apps\sales\server.q -p 5010 -dbPath C:/data/databases/prod_parallel

# Linux
q orchestration/orchestrator.q -p 8000 -dbPath /your/db/path -csvPath /your/csv/path
q apps/sales/server.q -p 5010 -dbPath /your/db/path
```

Expected orchestrator startup output:
```
========================================
Orchestrator ready
  DB:      /your/db/path
  CSV:     /your/csv/path
  RefreshUnits: transactions
  Sources:      1
========================================
```

---

### 4. What Is Not Platform-Specific

The following work identically on Linux — no changes needed:
- All `system "l "` paths (use ROOT + "/" + path already)
- `.j.k` / `.j.j` JSON parsing
- `read0`, `key`, `get`, `set`
- `.Q.en`, `.Q.opt`
- `hsym` symbol construction
- Timer `.z.ts` / `system "t"`
- All analytical logic in `lib/`

### Linux Porting Checklist

```
[ ] orchestration/orchestrator.q  — ROOT line
[ ] server/server_init.q          — ROOT line
[ ] apps/sales/server.q           — ROOT line
[ ] core/db_writer.q              — default .dbWriter.dbPath
[ ] orchestration/orchestrator.q  — argDbPath and argCsvPath defaults
[ ] server/server_init.q          — argDbPath default
```

---

## Debugging Guide

### Startup Failures

**Symptom:** `RefreshUnits:` / `Sources: 0` in orchestrator startup summary

Either the sources CSV wasn't found or failed to parse. Check:
```q
/ Verify the file exists
key hsym `$"C:/projects/kdb-infra/config/sources_sales.csv"

/ Load it manually and inspect
raw:("SSSSSSCCS"; enlist ",") 0: hsym `$"C:/projects/kdb-infra/config/sources_sales.csv"
raw
```

Also check that `data_refresh/*.q` files loaded — they must run before `sources_<app>.csv` registers refresh units. If a `.q` file fails to load, the `registerRefreshUnit` call at the bottom never runs.

---

**Symptom:** `[WARN] data_refresh load failed` during startup

The `.q` file in `apps/<app>/data_refresh/` has a syntax or load-order error. Test it directly:
```q
system "l apps/sales/data_refresh/transactions.q"
```

Check the output for the actual error. Common causes: namespace typo in the refresh function, referencing a function that hasn't loaded yet.

---

**Symptom:** `[WARN] catalog load failed` or catalog silently empty

The catalog CSV path is wrong, or the CSV has a parsing error. Test directly:
```q
.catalog.load["C:/projects/kdb-infra/config/catalog_sales.csv"; `sales]
.catalog.sourceMap
```

If `sourceMap` is empty `()!()` after this call, the CSV read failed. Check the file exists and the column count matches the format string `"SSSSSSSBSS"` (10 columns).

---

### Orchestrator Failures

**Symptom:** `New work items: 0` despite CSV files being present

Discovery didn't match any files. Diagnose:
```q
/ Test discovery directly
system "l lib/discovery.q"
.discovery.identifyWork[.orchestrator.source_config; hsym `$argCsvPath]
```

If that returns empty, check file patterns and date extraction:
```q
/ Test filePattern match
files:key hsym `$argCsvPath
files where files like "sales_transactions_*.csv"

/ Test date extraction for one filename
.discovery.extractDateFromFilename[`yyyy-mm-dd; "_"; "sales_transactions_2026-01-27.csv"]
/ Should return 2026.01.27, not 0Nd
```

If discovery returns results but work items are still 0, all matching files are already in the log as completed:
```q
.ingestionLog.tbl
.orchestrator.resetSource[`transactions; 2026.01.27]
```

---

**Symptom:** `[ERROR] No refresh function registered for refreshUnit: transactions`

The `registerRefreshUnit` call in `transactions.q` didn't run, meaning the file either failed to load or the call errored. Check:
```q
key .orchestrator.refreshRegistry     / should list registered units
system "l apps/sales/data_refresh/transactions.q"
```

---

**Symptom:** `REFRESH_ERROR:validation failed: ...`

Catalog validation blocked ingestion — a required column is missing from the CSV. The error message lists the missing columns. Either fix the source file or add a `source_field` alias in `catalog_sales.csv`.

---

**Symptom:** `REFRESH_ERROR:length`

Usually a downstream consequence of the sourceMap being empty — the CSV loader returns an empty/malformed table and the aggregation hits a length mismatch. Fix the sourceMap/catalog issue first.

If sourceMap is fine, the error is in `data_refresh/<unit>.q` aggregation logic — test the refresh function directly:
```q
sm:enlist[`sales_transactions]!enlist hsym `$"C:/data/csv/sales_transactions_2026-01-27.csv"
.orchestrator.refreshRegistry[`transactions][2026.01.27; sm]
```

---

**Symptom:** `isRunning` stuck — orchestrator skips every tick

If the orchestrator crashes mid-tick, the `isRunning` flag stays `1b`:
```q
`.orchestrator.isRunning set 0b
.orchestrator.orchestratorRun[]
```

---

### Server Failures

**Symptom:** `'.http.addRoute` on startup

`http.q` is not loaded. It must be loaded in `server_init.q` before `server.q` registers routes:
```q
/ In server/server_init.q, under "Server infrastructure":
system "l ",ROOT,"/server/http.q";
```

---

**Symptom:** HTTP POST returns `'type` (500 error)

The JSON `filters:{}` parses to a generic null or wrong type in q. Test the handler directly in q to get the real error:
```q
params:`field`measure`asofDate`prevDate`filters!(
  "region"; "total_revenue"; "2026-02-26"; "2026-02-25"; ()!());
.qryHandler.table[params]
```

Note: if using a data pump framework instead of HTTP, this is irrelevant — pass the dict directly.

---

**Symptom:** `'Not cached: sales_by_region`

The cache registration or load failed. Check:
```q
.cache.cacheList[]      / shows registered entries and row counts
key .cache.cacheData    / shows what actually loaded
```

If `cacheList[]` shows 0 rows, `.dbWriter.reload[]` failed or the HDB partition doesn't exist yet. Run the orchestrator first to create partitions, then restart the server.

---

### q Language Pitfalls

**`system "l"` inside a lambda doesn't populate the global namespace in KDB+ 4.x**

Always load files at top level. The orchestrator auto-discovery loop uses `@[system; ...]` which runs at top level — this is why it works. Never do:
```q
{system "l myfile.q"} each fileList   / broken — globals not populated
```

---

**`tables` is a reserved word in q**

Never use `tables` as a local variable name. Use `tblList`, `tblNames`, `tbls` etc.

---

**`@[f; args; handler]` vs `.[f; args; handler]`**

`@` is for single-argument functions. `.[f; argList; handler]` unpacks `argList` as separate positional arguments. Getting this wrong silently projects the function instead of calling it — no error, just wrong behavior.

---

**Symbol columns with spaces after casting**

If symbols display as `A M E R` instead of `AMER`, the cast is wrong. The catalog cast for symbol type must use `` `$tbl col `` not `` `$string tbl col ``.

---

**Dict key lookup returns null unexpectedly**

Check the key type:
```q
type key myDict   / 11h = symbol list (correct for source maps)
```

A string-keyed dict requires string lookup. A symbol-keyed dict requires symbol lookup. Mixing types silently returns null.

---

## Routine Operations

**Check orchestrator health:**
```q
.orchestrator.status[]
```

**Preview what would be ingested without running:**
```q
.orchestrator.dryRun[`sales]
/ prints each (refreshUnit, date, sources) that would dispatch, or BLOCKED if deps missing
```

**Manually trigger ingestion without waiting for timer:**
```q
`.orchestrator.isRunning set 0b
.orchestrator.orchestratorRun[]
```

**Manually refresh a specific refreshUnit+date:**
```q
.orchestrator.manualRefresh[`transactions; 2026.02.26]
```

**Reset a failed refreshUnit+date for reprocessing:**
```q
.orchestrator.resetSource[`transactions; 2026.01.27]
```

**Check ingestion log:**
```q
.ingestionLog.tbl
select from .ingestionLog.tbl where status=`failed
```

**Inspect cache:**
```q
.cache.cacheList[]
.cache.get `sales_by_region
```

**Test discovery for a specific filename:**
```q
/ dateFrom:filename
.discovery.extractDateFromFilename[`yyyy-mm-dd; "_"; "sales_transactions_2026-02-26.csv"]
/ Should return 2026.02.26 not 0Nd

/ dateFrom:folder — test directory name parse
.discovery.parseToken[`yyyy-mm-dd; "2026-02-26"]
/ Should return 2026.02.26 not 0Nd
```

**Test a query handler directly:**
```q
.qryHandler.table[`field`measure`asofDate`prevDate`filters`exclusions!(
  "region"; "total_revenue"; "2026-02-24"; "2026-01-27"; ()!(); ()!())]
```

---

## Ingestion Log Reference

The log shape changed in the refactoring from source-level to refreshUnit-level tracking:

| Column | Type | Notes |
|--------|------|-------|
| `refreshUnit` | symbol | The unit name from `registerRefreshUnit` |
| `date` | date | Partition date being processed |
| `status` | symbol | `` `processing ``, `` `completed ``, `` `failed `` |
| `tableCounts` | string | `"sales_transactions:207, sales_by_region:5"` |
| `warnings` | string | Semicolon-separated non-blocking warnings; `""` if clean |
| `startTime` | timestamp | When `markProcessing` was called |
| `endTime` | timestamp | When `markCompleted` or `markFailed` was called |

The orchestrator writes `markProcessing` before calling the refresh function, and `markCompleted` (with computed `tableCounts`) after a successful run. `markFailed` is written if the refresh function signals or returns a `"REFRESH_ERROR:..."` string.
