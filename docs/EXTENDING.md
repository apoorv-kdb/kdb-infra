# Extending: Adding a New Application

This guide walks through adding a new analytical application end-to-end. Everything follows the pattern established by the sales app. The steps are the same regardless of domain.

As a worked example, we'll add a **margin app** that ingests daily margin requirement data and serves movement and spot analytics.

---

## Overview: What Changes vs What Stays Fixed

**You write (per app):**
- `config/catalog_<app>.csv` — field definitions and source aliases
- `config/sources_<app>.csv` — source file registration (filePattern, discovery strategy)
- `apps/<app>/data_refresh/<unit>.q` — transform raw CSV to aggregated tables; self-registers
- `apps/<app>/server.q` — load catalog, register cache, expose functions

**You don't touch:**
- `orchestration/orchestrator.q` — auto-discovers new apps, no changes needed
- `core/` — csv_loader, db_writer, ingestion_log are shared infrastructure
- `lib/` — catalog, discovery, query handlers, filters are all reusable
- `server/` — cache and server_init are shared

There is no `config.q` or `core/` subfolder per app. Source registration is data (`sources_<app>.csv`), not code.

---

## Step 1: Define the Catalog CSV

Create `config/catalog_margin.csv`. One row per field per source alias.

```csv
app,table,field,label,type,role,format,enabled,source_field
margin,margin_summary,date,Date,date,temporal,,1,
margin,margin_summary,desk,Desk,symbol,categorical,,1,
margin,margin_summary,portfolio,Portfolio,symbol,categorical,,1,
margin,margin_summary,im_requirement,IM Requirement,float,value,currency,1,
margin,margin_summary,vm_requirement,VM Requirement,float,value,currency,1,
margin,margin_raw,date,Date,date,temporal,,0,date
margin,margin_raw,date,Date,date,temporal,,0,TRADE_DATE
margin,margin_raw,desk,Desk,symbol,categorical,,0,desk
margin,margin_raw,desk,Desk,symbol,categorical,,0,DESK_CODE
margin,margin_raw,portfolio,Portfolio,symbol,categorical,,0,portfolio
margin,margin_raw,im_requirement,IM Requirement,float,value,currency,0,im_req
margin,margin_raw,im_requirement,IM Requirement,float,value,currency,0,INITIAL_MARGIN
margin,margin_raw,vm_requirement,VM Requirement,float,value,currency,0,vm_req
```

**Key decisions in the catalog:**

- `margin_raw` rows have `enabled=0` — they drive ingestion and validation but are not exposed to consumers. The raw transaction table is an implementation detail.
- `margin_summary` rows have `enabled=1` — these are the aggregated fields that `.catHandler.fields` will return.
- Multiple rows per field in `margin_raw` = multiple accepted source aliases. If one system calls the field `im_req` and another calls it `INITIAL_MARGIN`, both map to canonical `im_requirement`.
- Leave `source_field` blank when the source column name already matches the canonical name.

See `docs/CATALOG.md` for full column reference.

---

## Step 2: Define the Sources CSV

Create `config/sources_margin.csv`. One row per source file type.

```csv
source,refreshUnit,filePattern,dateFrom,dateFormat,dateDelim,delimiter,required
margin_raw,margin_refresh,margin_*.csv,filename,yyyy-mm-dd,_,",",1
```

**Column reference:**

| Column | Purpose |
|--------|---------|
| `source` | Logical source name — matches the table name in `catalog_margin.csv` and the key used in `data_refresh.q` |
| `refreshUnit` | Groups sources that must be processed together; the orchestrator dispatches once per refreshUnit+date |
| `filePattern` | Glob matched against filenames in the CSV directory |
| `dateFrom` | Discovery strategy: `filename` or `folder` |
| `dateFormat` | How to parse the date token: `yyyymmdd`, `yyyy.mm.dd`, or `yyyy-mm-dd` |
| `dateDelim` | Character used to split the filename before date extraction (only for `dateFrom:filename`) |
| `delimiter` | Delimiter character inside the source data file |
| `required` | `1` — refreshUnit won't dispatch without this source present for the target date |

**File naming convention for `dateFrom:filename` with `dateDelim:_` and `dateFormat:yyyy-mm-dd`:**
Files named `margin_2026-01-27.csv` or `margin_run_2026-01-27.csv` will both work — the orchestrator splits on `_` and tests each token as a date, taking the first valid parse.

**Alternative: `dateFrom:folder`** — if your files arrive pre-sorted into date subdirectories:
```csv
source,refreshUnit,filePattern,dateFrom,dateFormat,dateDelim,delimiter,required
margin_raw,margin_refresh,margin_*.csv,folder,yyyy-mm-dd,,",",1
```
Files would live at `csvPath/2026-01-27/margin_*.csv`. `dateDelim` is unused for folder mode.

---

## Step 3: Write data_refresh/<unit>.q

Create `apps/margin/data_refresh/margin_refresh.q`.

The orchestrator calls this as `.marginCore.refresh[dt; sources]` where:
- `dt` is the date being processed (kdb+ date type)
- `sources` is a dict of `sourceName -> filepath symbol`

```q
/ apps/margin/data_refresh/margin_refresh.q

.marginCore.refresh:{[dt; sources]
  / 1. Load raw CSV — catalog handles rename, drop unmapped, type cast
  raw:.csv.loadCSV[`margin_raw; `margin; sources`margin_raw; ","];

  / 2. Validate — blocking on missing columns, non-blocking on nulls
  vr:.catalog.validate[`margin_raw; raw; `margin];
  if[not vr`valid;
    '"validation failed: ",("; " sv vr`errors)];

  if[count vr`warnings; {show "  [WARN] ",x} each vr`warnings];

  / 3. Aggregate to summary level
  summary:0! select
      im_requirement: sum im_requirement,
      vm_requirement: sum vm_requirement
    by date, desk, portfolio from raw;

  / 4. Write partitions
  dates:asc distinct summary`date;
  {[raw; summary; d]
    rawDay:    select from raw     where date=d;
    sumDay:    select from summary where date=d;
    .dbWriter.writeMultiple[`margin_raw`margin_summary!(rawDay; sumDay); d];
  }[raw; summary;] each dates;

  / 5. Reload HDB
  .dbWriter.reload[];

  show "  Ingested ",string[count raw]," rows for ",string[count dates]," dates";
 }

/ Self-registration — these two lines are mandatory at the bottom of every data_refresh/*.q
.dbWriter.addDomain[`margin];
.orchestrator.registerRefreshUnit[`margin_refresh; .marginCore.refresh];
```

The pattern is always the same: load → validate → aggregate → write → reload.

**Important:** signal (`'`) on validation failure rather than calling `.ingestionLog.markFailed` directly. The orchestrator catches the signal, marks the refreshUnit failed, and logs the error message. Log management is the orchestrator's responsibility; refresh functions only transform and write.

---

## Step 4: Write server.q

Create `apps/margin/server.q`. Copy from `apps/sales/server.q` and change the app name, catalog path, and cached tables. Replace the function exposure block with your framework's registration calls.

```q
/ apps/margin/server.q

ROOT:rtrim ssr[{$[10h=type x;x;first x]} system "cd"; "\\"; "/"]
system "l ",ROOT,"/server/server_init.q";

system "l ",ROOT,"/lib/cat_handlers.q";
system "l ",ROOT,"/lib/query.q";

opts:.Q.opt .z.x;
.srv.catPath:$[`catPath in key opts; first opts`catPath; ROOT,"/config/catalog_margin.csv"];
.catalog.load[.srv.catPath; `margin];

.cache.register[`margin_summary; `margin_summary; 9999; ::];
.cache.loadAll[];
.cache.startRefresh[600000];

/ Expose functions via your framework's registration mechanism:
/ .myFramework.expose `.catHandler.fields
/ .myFramework.expose `.catHandler.filterOptions
/ .myFramework.expose `.qryHandler.table
/ .myFramework.expose `.qryHandler.spot
/ .myFramework.expose `.qryHandler.trend

show "Margin server ready";
```

Start on its own port:
```bash
q apps/margin/server.q -p 5011 -dbPath /data/databases/prod_parallel
```

The orchestrator auto-discovers the app from the `apps/` directory. No changes to shared infrastructure needed.

---

## End-to-End Checklist

```
[ ] 1.  Create config/catalog_<app>.csv
[ ] 2.  Create config/sources_<app>.csv
[ ] 3.  Drop CSV files into /data/csv/ following the filePattern and date convention
[ ] 4.  Create apps/<app>/data_refresh/<unit>.q with self-registration lines at bottom
[ ] 5.  Create apps/<app>/server.q
[ ] 6.  Restart orchestrator — confirm new RefreshUnits in startup output
[ ] 7.  Run .orchestrator.dryRun[`<app>] — verify correct work items identified
[ ] 8.  Confirm orchestrator tick ingests files successfully
[ ] 9.  Start app server on new port
[ ] 10. Confirm .catHandler.fields returns expected fields
[ ] 11. Confirm .qryHandler.table returns data
```

---

## Testing Discovery in Isolation

Before running a full orchestrator tick, validate that your source config correctly identifies files:

```q
/ Load discovery module standalone
system "l lib/discovery.q"

/ Build a test source config row (mirroring your sources_<app>.csv)
testSrc:([]
  source:      enlist `margin_raw;
  refreshUnit: enlist `margin_refresh;
  app:         enlist `margin;
  required:    enlist 1b;
  filePattern: enlist `margin_*.csv;
  dateFrom:    enlist `filename;
  dateFormat:  enlist `yyyy-mm-dd;
  dateDelim:   enlist "_";
  delimiter:   enlist ","
 );

/ Run discovery against your actual CSV directory
work:.discovery.identifyWork[testSrc; hsym `$/data/csv]

/ Inspect
count work
work
```

If `work` is empty, check that filenames match `filePattern` and that a date token parses correctly:
```q
.discovery.extractDateFromFilename[`yyyy-mm-dd; "_"; "margin_2026-01-27.csv"]
/ Should return 2026.01.27, not 0Nd
```

---

## Common Pitfalls

**No files found by discovery** — verify `filePattern` matches actual filenames and that `dateDelim`/`dateFormat` correctly extract a date. Test with `.discovery.extractDateFromFilename` or `.discovery.parseToken` directly.

**`tables` is a reserved word in q** — never use as a local variable. Use `tblList`, `tblNames`, etc.

**`system "l"` inside a lambda doesn't populate global namespace** — always load files at top level. The orchestrator auto-discovery uses `@[system; ...]` at top level for this reason.

**Symbol columns with spaces** — if symbols look like `A M E R` instead of `AMER`, the cast is wrong. `.catalog.cast` must use `` `$tbl col `` not `` `$string tbl col `` for symbol columns.

**isRunning flag stuck** — if the orchestrator crashes mid-tick, `.orchestrator.isRunning` stays `1b`. Clear manually:
```q
`.orchestrator.isRunning set 0b
```

**Prev date not in database** — `.qryHandler.table` returns `prevValue:0` if the prev date has no data. Confirm both test dates are within the ingested range.

**Domain not registered** — `db_writer.q` enforces naming convention: table names must start with a registered domain. The `.dbWriter.addDomain[`appname]` line at the bottom of `data_refresh/<unit>.q` handles this. If missing, writes will fail with a type error.

**sources_<app>.csv not found** — the orchestrator looks for `config/sources_<app>.csv` relative to ROOT. If missing, no sources are registered and the app's refresh units are unreachable.

---

## Planned Extension: Presets and Authentication

### Design

Presets are view configurations — mode, measure, window, groupBy fields, filters, exclusions. Dates are intentionally excluded: a preset describes how to look at data, not when.

**Storage:** one JSON file per app server — `config/presets_<app>.json`:

```json
{
  "groups": {
    "credit-desk": {
      "users": ["user1", "user2"],
      "presets": [
        {
          "id": "p001",
          "name": "Morning View",
          "isDefault": true,
          "mode": "movement",
          "measure": "total_revenue",
          "window": "30d",
          "groupBy": [{"field": "region", "showTable": true, "showChart": true}],
          "filters": {},
          "exclusions": {}
        }
      ]
    }
  }
}
```

**Access control:**
- LDAP gates server access — binary per server, driven by LDAP group membership
- Custom groups in the JSON file control which presets a user sees
- A user in multiple groups sees the union of those groups' presets
- Preset names must be unique across all groups (enforced at startup)
- Each group can have at most one `isDefault: true` preset
- If a user is in multiple groups each with a default, no preset auto-loads — user picks manually

**New q modules:**

`lib/auth.q` — LDAP and group resolution:
```q
.auth.isAllowed[user]     / check user against LDAP group for this server
.auth.groupsFor[user]     / return list of custom groups from presets JSON
```

`lib/presets.q` — preset storage and retrieval:
```q
.presets.forUser[user]    / resolve groups, union presets, return flat list
.presets.reload[]         / hot reload JSON without restarting server
```

Wired into `.z.pg` / `.z.po` at connection time for access control. One function exposed per app server for preset retrieval.

**Preset management:** admins edit `presets_<app>.json` directly and call `.presets.reload[]` from the q console. No write endpoints — save is config-file only in this phase.

### Build Order When Ready

1. `lib/auth.q` — LDAP connection check
2. `lib/presets.q` — JSON load, group resolution, startup validation
3. Wire `.auth.isAllowed` into `.z.pg` in each app server
4. Expose `.presets.forUser` via framework

Estimated effort: 2-3 days. LDAP integration is the main variable.

---

## Troubleshooting a Data Refresh

The orchestrator is just a scheduler. Everything meaningful happens in `data_refresh/<unit>.q`. You can test your refresh function completely independently of the orchestrator — and you should, before letting the orchestrator call it.

### Step 1 — Check the ingestion log

After a tick, check what happened:

```q
/ See all entries
.ingestionLog.tbl

/ See only failures
select from .ingestionLog.tbl where status=`failed
```

If entries are in `failed` status, reset them before retrying — otherwise the orchestrator will skip them as already processed:

```q
/ Reset one refreshUnit+date
.orchestrator.resetSource[`transactions; 2026.01.27]

/ Reset all failed
failed:exec distinct (refreshUnit; date) from .ingestionLog.tbl where status=`failed;
.orchestrator.resetSource'[failed]
```

---

### Step 2 — Call the refresh function directly

Pull the filepath from the ingestion log and call your refresh function manually. This bypasses all orchestrator wrapping and gives you the full q error with file and line number:

```q
/ Get a failed entry
r:first select from .ingestionLog.tbl where status=`failed

/ Build sourceMap (use actual filepath for this refreshUnit)
sm:(enlist `margin_raw)!enlist hsym `$"/data/csv/margin_2026-01-27.csv"

/ Call refresh directly — full error visible here
.marginCore.refresh[r`date; sm]
```

---

### Step 3 — Test each step in isolation

If the refresh function errors, test each step individually:

```q
/ Test CSV load
raw:.csv.loadCSV[`margin_raw; `margin; sm`margin_raw; ","]
count raw
cols raw
meta raw

/ Test catalog validation
vr:.catalog.validate[`margin_raw; raw; `margin]
vr`valid
vr`errors

/ Test aggregation (paste your aggregation logic directly)
agg:0! select im_requirement:sum im_requirement, vm_requirement:sum vm_requirement
  by date, desk, portfolio from raw
count agg

/ Test write for one date
d:first asc distinct agg`date
.dbWriter.writeMultiple[`margin_summary!enlist select from agg where date=d; d]
```

---

### Common Causes of `REFRESH_ERROR:length`

- **Embedded commas in CSV fields** — `csv_loader.q` handles quoted fields (e.g. `"Smith, John"`). Unquoted commas in fields are ambiguous and cannot be parsed — fix at source or use a different delimiter.
- **Column count mismatch** — header has N columns but a data row has N+1 or N-1. Check `count "," vs each read0 fp` to find the offending rows.
- **Empty aggregation** — if the CSV loads but has no rows matching the date filter, the aggregation returns empty and downstream writes fail. Check `count raw` after load.

---

## Notes on Catalog Design

### Skipping the catalog for clean sources

If your source CSV already uses clean, consistent column names matching your canonical field names, you don't need to catalog the raw table. Load directly in `data_refresh/<unit>.q`:

```q
/ Load with explicit type string — no catalog involvement
raw:("DSSFF"; enlist ",") 0: sources`your_source;

/ Validate manually
missing:`date`desk`revenue where not (`date`desk`revenue) in cols raw;
if[count missing;
  '"missing columns: ",", " sv string missing];

/ Aggregate and write as normal
```

Only catalog the aggregated output table (`enabled=1`). The raw source never touches the catalog.

### Derived table catalog is currently manual

Today you write catalog entries for both the raw source table and the aggregated output table. The derived table entries are boilerplate — the field names, types, and roles are implied by the aggregation logic in `data_refresh/<unit>.q`.

This is a known limitation. A future improvement will infer or scaffold the derived table catalog from the raw source catalog and aggregation declarations. For now: copy field names from your aggregation, set `enabled=1`, inherit types from the corresponding raw fields.
