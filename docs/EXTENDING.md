# Extending: Adding a New Application

This guide walks through adding a new analytical application end-to-end. Everything follows the pattern established by the sales app. The steps are the same regardless of domain.

As a worked example, we'll add a **margin app** that ingests daily margin requirement data and serves movement and spot analytics.

---

## Overview: What Changes vs What Stays Fixed

**You write (per app):**
- `config/catalog_<app>.csv` — field definitions and source aliases
- `apps/<app>/core/data_refresh.q` — transform raw CSV to aggregated tables
- `apps/<app>/core/config.q` — register sources with the orchestrator
- `apps/<app>/server.q` — load catalog, register cache, expose functions

**You don't touch:**
- `orchestration/orchestrator.q` — auto-discovers new apps, no changes needed
- `core/` — csv_loader, db_writer, ingestion_log are shared infrastructure
- `lib/` — catalog, query handlers, filters are all reusable
- `server/` — cache and server_init are shared

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

## Step 2: Write data_refresh.q

Create `apps/margin/core/data_refresh.q`.

The orchestrator calls this as `.marginCore.refresh[dt; sources]` where:
- `dt` is the date being processed (kdb+ date type)
- `sources` is a dict of `sourceName -> filepath`

```q
/ apps/margin/core/data_refresh.q

.marginCore.refresh:{[dt; sources]
  / 1. Load raw CSV — catalog handles rename, drop unmapped, type cast
  raw:.csv.loadCSV[`margin_raw; `margin; sources`margin_raw; ","];

  / 2. Validate — blocking on missing columns, non-blocking on nulls
  vr:.catalog.validate[`margin_raw; raw; `margin];
  if[not vr`valid;
    .ingestionLog.markFailed[`margin_raw; dt; "; " sv vr`errors];
    :()];

  if[count vr`warnings; {show "  [WARN] ",x} each vr`warnings];

  / 3. Aggregate to summary level
  summary:0! select
      im_requirement: sum im_requirement,
      vm_requirement: sum vm_requirement
    by date, desk, portfolio from raw;

  / 4. Write partitions
  dates:asc distinct summary`date;
  {[raw; summary; d]
    rawDay:    select from raw     where date = d;
    sumDay:    select from summary where date = d;
    .dbWriter.writeMultiple[`margin_raw`margin_summary!(rawDay; sumDay); d];
  }[raw; summary;] each dates;

  / 5. Reload HDB
  .dbWriter.reload[];

  show "  Ingested ",string[count raw]," rows for ",string[count dates]," dates";
  .ingestionLog.markCompleted[`margin_raw; first dates; count raw];
 }
```

The pattern is always the same: load -> validate -> aggregate -> write -> reload.

---

## Step 3: Write config.q

Create `apps/margin/core/config.q`.

```q
/ apps/margin/core/config.q

.dbWriter.addDomain[`margin];

csvDir:$[`argCsvPath in key `.; argCsvPath;
         `csvPath in key .Q.opt .z.x; first (.Q.opt .z.x)`csvPath;
         "/data/csv"];

.orchestrator.addSources enlist
  `source`app`required`directory`filePattern`delimiter`frequency!(
    `margin_raw; `margin; 1b; hsym `$csvDir; `margin_*.csv; ","; `daily);

.orchestrator.registerApp[`margin; .marginCore.refresh];
```

**File pattern:** `margin_*.csv` matches any file starting with `margin_`. Name files `margin_2026.01.27.csv` — the orchestrator extracts the date automatically.

---

## Step 4: Write server.q

Create `apps/margin/server.q`. Copy from `apps/sales/server.q` and change the app name, catalog path, and cached tables. Replace the function exposure block with your framework's registration calls.

```q
/ apps/margin/server.q

ROOT:rtrim {$[10h=type x;x;first x]} system "cd"
system "l ",ROOT,"/server/server_init.q";

loadDomainConfigs[`margin];

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

The orchestrator auto-discovers the app from the `apps/` directory. No changes to `orchestrator.q` needed.

---

## End-to-End Checklist

```
[ ] 1.  Create config/catalog_<app>.csv
[ ] 2.  Drop CSV files into /data/csv/ with date in filename
[ ] 3.  Create apps/<app>/core/data_refresh.q
[ ] 4.  Create apps/<app>/core/config.q
[ ] 5.  Create apps/<app>/server.q
[ ] 6.  Restart orchestrator — confirm new app in "Apps:" startup output
[ ] 7.  Confirm orchestrator tick ingests files successfully
[ ] 8.  Start app server on new port
[ ] 9.  Confirm .catHandler.fields returns expected fields
[ ] 10. Confirm .qryHandler.table returns data
```

---

## Common Pitfalls

**Date not in filename** — orchestrator silently skips files where it cannot extract a date. Filename must contain `YYYY-MM-DD`, `YYYY_MM_DD`, `YYYY.MM.DD`, or `YYYYMMDD`. Test with:
```q
.orchestrator.extractDate[`$"yourfilename.csv"]
```
Should return a date, not `0Nd`.

**`tables` is a reserved word in q** — never use as a local variable. Use `tblList`, `tblNames`, etc.

**`system "l"` inside a lambda doesn't populate global namespace** — always load files at top level. The orchestrator auto-discovery uses `@[system; ...]` at top level for this reason.

**Symbol columns with spaces** — if symbols look like `A M E R` instead of `AMER`, the cast is wrong. `.catalog.cast` must use `` `$tbl col `` not `` `$string tbl col `` for symbol columns.

**isRunning flag stuck** — if the orchestrator crashes mid-tick, `.orchestrator.isRunning` stays `1b`. Clear manually:
```q
`.orchestrator.isRunning set 0b
```

**Prev date not in database** — `.qryHandler.table` returns `prevValue:0` if the prev date has no data. Confirm both test dates are within the ingested range.

**Domain not registered** — `db_writer.q` enforces naming convention: table names must start with a registered domain. Call `.dbWriter.addDomain` in `config.q` before writing.

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
