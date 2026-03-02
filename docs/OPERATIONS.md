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
| `apps/sales/core/config.q` | `csvDir` | `"C:/data/csv"` | `"/your/csv/path"` |

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
[ ] apps/sales/core/config.q      — csvDir default
```

---

## Debugging Guide

### Startup Failures

**Symptom:** `Sources: 0` / `Apps: 0` in orchestrator startup summary

The catalog didn't load. The most common cause is using `@` instead of `.` for a multi-argument error-protected call:

```q
/ WRONG — @[f; args; handler] passes args as a single argument, projecting f instead of calling it
@[.catalog.load; (catPath; `$string app); {[e] ...}]

/ CORRECT — .[f; args; handler] unpacks the list as separate arguments
.[.catalog.load; (catPath; `$string app); {[e] ...}]
```

Rule: use `@` only for single-argument functions. Use `.` for two or more arguments.

---

**Symptom:** `[WARN] Failed: .salesCore.refresh` during config.q load

`config.q` calls `.orchestrator.registerApp[`sales; .salesCore.refresh]` but `.salesCore.refresh` doesn't exist yet. This means `data_refresh.q` failed to load before `config.q` ran.

Check the load order in `orchestrator.q` — `data_refresh.q` must load before `config.q`. Also check for errors in `data_refresh.q` itself:

```q
system "l apps/sales/core/data_refresh.q"
```

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

**Symptom:** `[WARN] No source map for table: sales_transactions`

The catalog's `sourceMap` is empty for that table. Either the catalog didn't load (see above) or the table name in `data_refresh.q` doesn't match the table name in the catalog CSV.

Diagnose:
```q
key .catalog.sourceMap               / should list table names
.catalog.sourceMap[`sales_transactions]   / should return a string->symbol dict
```

---

**Symptom:** `REFRESH_ERROR:length`

Usually a downstream consequence of the sourceMap being empty — the CSV loader returns an empty/malformed table and the aggregation hits a length mismatch. Fix the sourceMap issue first.

If sourceMap is fine, the error is in `data_refresh.q` aggregation logic — test the refresh function directly:

```q
sm:enlist[`sales_transactions]!enlist hsym `$"C:/data/csv/sales_transactions_2026-01-27.csv"
.orchestrator.appRegistry[`sales][2026.01.27; sm]
```

---

**Symptom:** `[ERROR] Scan failed: type`

The `like` call in `scanAllSources` is getting a type mismatch. The `filePattern` column must be `symbol` type. Check `source_config`:

```q
meta .orchestrator.source_config
```

The `filePattern` column should show type `s`. If it's a string list, the `addSources` call in `config.q` is passing a string instead of a symbol for `filePattern`.

---

**Symptom:** `isRunning` stuck — orchestrator skips every tick

If the orchestrator crashes mid-tick, the `isRunning` flag stays `1b`:

```q
`.orchestrator.isRunning set 0b
.orchestrator.orchestratorRun[]
```

---

**Symptom:** Files found but `New work items: 0`

All files are already marked completed in the ingestion log. To force reprocessing:

```q
/ Reprocess one source+date
.orchestrator.resetSource[`sales_transactions; 2026.01.27]

/ Check what's in the log
.ingestionLog.tbl
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

The JSON `filters:{}` parses to a generic null or wrong type in q. Test the handler directly in q to get the real error — HTTP swallows the stack trace:

```q
params:`field`measure`asofDate`prevDate`filters!("region"; "total_revenue"; "2026-02-26"; "2026-02-25"; ()!());
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

**Manually trigger ingestion without waiting for timer:**
```q
`.orchestrator.isRunning set 0b
.orchestrator.orchestratorRun[]
```

**Manually refresh a specific date:**
```q
.orchestrator.manualRefresh[`sales; 2026.02.26]
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

**Test date extraction from filename:**
```q
.orchestrator.extractDate[`$"sales_transactions_2026-02-26.csv"]
/ Should return 2026.02.26 not 0Nd
```
