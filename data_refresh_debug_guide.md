# KDB+ Infrastructure — Data Refresh Debug Guide

Step-by-step isolation of pipeline failures | Windows + Linux

---

## How to Use This Guide

The pipeline has five phases. When `.orchestrator.orchestratorRun[]` produces unexpected results, work through the phases in order from the top. Each phase gives you exact q commands to run, what to look for, and what to do if the output is wrong.

**Golden rule:** if the orchestrator runs silently but nothing appears in the DB, start at Phase 1 and execute every check manually. Do not skip phases.

> **NOTE:**
> Always run `.ingestionLog.init[]` before re-testing so the orchestrator treats the file as new work.

---

## Phase 1 — File Discovery

Verify the orchestrator can find your CSV on disk and extract a valid date from the filename.

### Run
```q
scanned:.orchestrator.scanAllSources[]
show scanned
```

### Expected output
```
source             date       filepath
--------------------------------------------------------------------------
sales_transactions 2024.02.12 :C:/data/csv/sales_transactions_20240212.csv
```

### If scanned is empty

Check the source config registration:
```q
show .orchestrator.source_config
```

Then verify each field manually:

| Check | Command |
|---|---|
| directory | `key .orchestrator.source_config[0]\`directory` |
| filePattern | `show .orchestrator.source_config[0]\`filePattern` |
| file exists? | `key hsym \`$"C:/data/csv/sales_transactions_20240212.csv"` |
| pattern match? | `` enlist[`sales_transactions_20240212.csv] like "sales_transactions_*.csv" `` |
| date parse? | `.orchestrator.extractDate \`sales_transactions_20240212.csv` |

Common causes:
- `directory` uses Linux path instead of `hsym \`$"C:/data/csv"`
- `filePattern` does not match filename (check case sensitivity)

---

## Phase 2 — Work Identification

Verify the orchestrator considers this file as new work — not already completed in the ingestion log.

### Run
```q
show .ingestionLog.tbl

work:.orchestrator.identifyWork[scanned]
show work
```

### Expected output
```
/ ingestion log should be empty or show no completed row for this source+date

/ work should match scanned:
source             date       filepath
--------------------------------------------------------------------------
sales_transactions 2024.02.12 :C:/data/csv/sales_transactions_20240212.csv
```

### If work is empty but file exists

The ingestion log has this source+date marked completed. Use the built-in reset helper:
```q
.orchestrator.resetSource[`sales_transactions; 2024.02.12]
```

This removes only this source's row from both the in-memory and persisted log. Other sources for the same date are unaffected.

To wipe the entire in-memory log (testing only):
```q
.ingestionLog.init[]
```

---

## Phase 3 — CSV Loading and Validation

Verify the CSV can be read from disk, types cast correctly, and validation passes.

### Step 3a — Read raw file
```q
fp:first exec filepath from scanned where source=`sales_transactions

/ Confirm file is accessible
key fp

/ Read raw lines
read0 fp
```

Expected: `key` returns the filepath symbol (not `()`). `read0` shows your header row and data rows.

### Step 3b — Load with schema
```q
schema:.validator.getSchema[`sales_transactions]
show schema

/ Load all columns as strings - one * per column
raw:((count schema`columns)#"*"; enlist ",") 0: fp
show cols raw
show 3#raw
```

> **ERROR: `'type` on the `0:` line**
> Fix: delimiter must be a char not a string. `first ","` returns `","`.
>
> **ERROR: column count mismatch**
> Fix: `count schema\`columns` must equal actual column count in CSV.

### Step 3c — Build typeMap and cast

```q
/ Build typeMap correctly - {x} each converts types string to list of chars
typeMap:schema`columns!{x} each schema`types
show typeMap

/ Cast each column individually to find the bad one
{[raw; typeMap; col]
  typ:typeMap col;
  show string[col],": ";
  $[typ in "Ss";
    show `$raw col;
    show @[{[t;v] (t$)v}[typ]; raw col; {[e] "FAILED: ",e}]]
}[raw; typeMap] each schema`columns
```

> **NOTE on type chars:**
> Schema types use uppercase: `"DSSJI"`. The cast operator also uses uppercase: `"D"$`, `"J"$`, `"I"$`.
> Do NOT lowercase type chars before casting — `"d"$` on a date list returns `0h` (wrong).
> Symbols are special — use `` `$col `` not `"s"$col` (which fails on char lists).

### Step 3d — Full loadCSV
```q
txns:.csv.loadCSV[`sales_transactions; fp; ","]
count txns
type each flip txns
```

Expected: typed table with correct row count. `type each flip` shows `-14 -11 -11 -7 -6` for `DSSJI`.

> **ERROR: `'type` in `notNull`**
> Fix: `null` fails on symbol columns. `notNull` checks `vals = \`` for `11h` type columns.
> Verify the function is correct:
> ```q
> .validator.notNull
> / Should contain: $[11h = abs type vals; sum vals = `; sum null vals]
> ```

---

## Phase 4 — DB Write

Verify the refresh function writes both tables to the partitioned database.

### Step 4a — Build sourceMap manually
```q
dt:first exec date from scanned where source=`sales_transactions
fp:first exec filepath from scanned where source=`sales_transactions

sourceMap:(enlist `sales_transactions)!(enlist fp)
show sourceMap
show type each sourceMap
```

Expected: `type each sourceMap` returns `sales_transactions | -11` (not `11h` which would be a list).

### Step 4b — Call refresh directly
```q
/ No error trapping - errors will surface immediately
.salesCore.refresh[dt; sourceMap]
```

Expected:
```
"  Saved sales_transactions for 2024.02.12: 7 rows"
"  Saved sales_by_region for 2024.02.12: 3 rows"
```

> **ERROR: `'type` in writePartition**
> Fix: check that `tbl` is unkeyed (type `98h`). Use `0!` to unkey if needed.
>
> **ERROR: `'Enum failed`**
> Fix: DB directory may not exist. Run: `mkdir C:\data\databases\prod_parallel`
>
> **ERROR: `'Write failed`**
> Fix: use `.` not `@` for 2-arg protected eval: `.[{[pp;d] pp set d}; (partPath; data); handler]`

### Step 4c — Confirm on disk
```q
key `$":C:/data/databases/prod_parallel/",string dt
```

Expected: `` `s#`infra_ingestion_log`sales_by_region`sales_transactions ``

If this returns nothing but no error was thrown, check Windows Explorer:
```q
system "dir C:\\data\\databases\\prod_parallel"
```

---

## Phase 5 — Orchestrator Dispatch

Only needed if Phases 1–4 all pass manually but `.orchestrator.orchestratorRun[]` still produces no data.

### Step 5a — Check app is registered
```q
.orchestrator.appRegistry
```

If empty, reload config and check for errors:
```q
system "l C:/projects/kdb-infra/apps/sales/core/config.q"
.orchestrator.appRegistry
```

> **Common cause of empty registry:** a line in `config.q` throws before `registerApp` is reached.
> Any reference to a module that isn't loaded (e.g. `.retention.classifyBatch`) will silently abort the file.
> The error will surface when you reload config manually.

### Step 5b — Trace groupByApp output
```q
.ingestionLog.init[]
scanned:.orchestrator.scanAllSources[]
work:.orchestrator.identifyWork[scanned]
grouped:.orchestrator.groupByApp[work]
row:(0!grouped) 0

show row`app
show row`date
show row`sources
show row`filepaths
show type each row`filepaths
```

`sources` and `filepaths` come back as enlisted lists from the by-grouping. They must be razed before building sourceMap:

```q
sourceMap:(raze row`sources)!(raze row`filepaths)
show sourceMap
show type each sourceMap
```

> **ERROR: `type each sourceMap` returns `11h` instead of `-11h`**
> Fix: `raze` not being applied before building `sourceMap` in `orchestrator.q`.

### Step 5c — Call dispatchApp directly
```q
appName:`sales_core
dt:2024.02.12
sourceMap:(raze row`sources)!(raze row`filepaths)

.[.orchestrator.appRegistry appName; (dt; sourceMap); {[e] show "ERROR: ",e}]
```

> **NOTE:** Always use `.` (dot apply) not `@` for multi-arg protected eval.
> `@` with a multi-arg function returns a projection (`104h`) silently — no error, no result.

---

## Quick Reference — Common Errors

| Error / Symptom | Likely Cause | Fix |
|---|---|---|
| `scanned` is empty | Wrong path format, filePattern mismatch | Verify `key` on directory, confirm `like` match |
| `work` is empty | File already completed in ingestion log | `.orchestrator.resetSource[src; dt]` |
| `File not found` | filepath missing `:` prefix | Use `hsym` or prefix with `:` |
| `0: 'type` | Wrong delimiter type or wrong column count | `((count schema\`columns)#"*"; enlist first delim) 0: fp` |
| `'type` in `notNull` | `null` called on symbol column | `notNull` must check `vals = \`` for type `11h` |
| `Cast failed: region` | `"s"$` used on symbol list | Use `` `$col `` for symbols |
| `'type` building `typeMap` | `11h ! 10h` fails | `schema\`columns!{x} each schema\`types` |
| `'type` casting date | `lower typ` used before `$` | Keep type chars uppercase — `"D"$` not `"d"$` |
| `recordCount 'type` | `count get tblPath` returns int not long | Cast at source: `` `long$count get tblPath `` |
| `'length` in `markFailed` | String passed to generic list column | `markFailed` must use `enlist msg` in update |
| `No refresh function registered` | `config.q` threw before `registerApp` | Reload config manually and check for errors |
| `'nyi` on table column assignment | Column-level `tbl[idx;col]:val` not supported | Use functional update or `enlist` in `update` |
| Result type `104h` | `@` used to call 2-arg function | Use `.` not `@` for multi-arg protected eval |
| `The syntax is incorrect` | Windows system cmd receiving forward slashes | `ssr[path; "/"; "\\"]` before `system` call |

---

## Key Facts to Remember

### `@` vs `.` for protected eval

```q
/ Single-arg function
@[fn; singleArg; errHandler]

/ Multi-arg function - MUST use dot apply
.[fn; (arg1; arg2); errHandler]
```

Using `@` with a multi-arg function returns a **projection** (type `104h`) silently — no error thrown, nothing executed.

---

### Type chars in q

Schema types and `$` casting both use **uppercase**: `"D"`, `"S"`, `"J"`, `"I"`, `"F"`.

Do **not** lowercase before casting. `"d"$` on a date list returns `0h`. `"D"$` works correctly.

Symbols are special — `"s"$` fails on lists. Use `` `$ `` directly:
```q
`$raw`region       / correct
"s"$raw`region     / WRONG - fails on char list
```

When building a `typeMap` dict, use `{x} each` to convert the types string to a list of chars:
```q
typeMap:schema`columns!{x} each schema`types    / correct - produces 11h!0h
typeMap:schema`columns!schema`types              / WRONG - 11h!10h fails
```

---

### Null checking for symbol columns

`null` does not work on symbol lists (`11h`). Use `vals = \`` instead:
```q
nullCount:$[11h = abs type vals;
  sum vals = `;      / symbol null check
  sum null vals];    / all other types
```

---

### kdb+ file paths on Windows

kdb+ uses forward slashes internally: `` `:C:/data/csv/file.csv ``

Windows system commands need backslashes:
```q
ssr[path; "/"; "\\"]
```

`hsym` adds the `:` prefix automatically: `hsym \`$"C:/data/csv"` → `` `:C:/data/csv ``

---

### Ingestion log and reprocessing

```q
/ Preferred - removes only this source's row, other sources for same date unaffected
.orchestrator.resetSource[`sales_transactions; 2024.02.12]

/ Nuclear - wipes entire in-memory log (DB copy survives until next reload)
.ingestionLog.init[]
```

---

### Always verify the in-memory function

After editing a `.q` file, restart the process. The function in memory is what runs — not what is on disk. After any edit verify:

```q
.csv.typeCast
.validator.notNull
.orchestrator.dispatchApp
```

### Bare `/` comment trap

A lone `/` on its own line starts a multi-line comment block and silently swallows everything after it. Always write `/ ---` or add text. To check a file:
```cmd
findstr /n "^/$" core\validator.q
```
