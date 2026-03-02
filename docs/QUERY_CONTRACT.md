# Query Contract

Integration reference for consumers of the app server q functions. All functions are called directly via the data pump framework — no HTTP required.

---

## Catalog Functions

### `.catHandler.fields[]`

Returns enabled fields for the app with display metadata.

**Arguments:** none

**Returns:** list of dicts

```q
.catHandler.fields[]
```

```
field          label          format    fieldType
-------------------------------------------------
product        Product                  categorical
region         Region                   categorical
total_quantity Total Quantity integer   value
total_revenue  Total Revenue  currency  value
```

**Notes:**
- `temporal` fields (date columns) are never returned regardless of `enabled` flag
- `fieldType` maps to `role` in the catalog (`categorical` or `value`)
- Use `fieldType=categorical` fields as `field`/`categoryField` params in query handlers
- Use `fieldType=value` fields as `measure` params in query handlers

---

### `.catHandler.filterOptions[]`

Returns all distinct values for categorical fields. Used to populate filter UI dropdowns.

**Arguments:** none

**Returns:** list of dicts

```q
.catHandler.filterOptions[]
```

```
key     value
-------------
product WidgetA
product WidgetB
product WidgetC
region  AMER
region  APAC
region  EMEA
```

---

## Query Handlers

### `.qryHandler.table` — Movement (DoD Comparison)

Compares two dates for a categorical field against a numeric measure. Returns absolute change and change %.

**Arguments:** dict with keys:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `field` | string | yes | Categorical field to group by (e.g. `"region"`) |
| `measure` | string | yes | Numeric measure to aggregate (e.g. `"total_revenue"`) |
| `asofDate` | string | yes | Primary date in `YYYY-MM-DD` format |
| `prevDate` | string | yes | Comparison date in `YYYY-MM-DD` format |
| `filters` | dict | no | Include filters — `symbol!string list`. Empty dict `()!()` means no filter |
| `exclusions` | dict | no | Exclude filters — same format as `filters` |

**Returns:** list of dicts, one per unique field value

```q
params:`field`measure`asofDate`prevDate`filters`exclusions!(
  "region"; "total_revenue"; "2026-02-26"; "2026-02-25"; ()!(); ()!());
.qryHandler.table[params]
```

```
region asofValue prevValue change  changePct
--------------------------------------------
"AMER" 21134.34  19676.95  1457.39 0.07406585
"APAC" 9623.16   8504.35   1118.81 0.1315574
"EMEA" 14431.35  14130.27  301.08  0.02130745
```

**Filter example** — restrict to AMER and APAC only:

```q
params:`field`measure`asofDate`prevDate`filters`exclusions!(
  "region"; "total_revenue"; "2026-02-26"; "2026-02-25";
  (enlist `region)!enlist ("AMER"; "APAC");
  ()!());
.qryHandler.table[params]
```

**Notes:**
- `field` must be `categorical` role in catalog
- `measure` must be `value` role in catalog
- Both dates must exist in the HDB — if `prevDate` has no data, `prevValue` returns `0f`
- `changePct` is `0f` when `prevValue` is `0f`

---

### `.qryHandler.spot` — Spot (Single Date Snapshot)

Single date breakdown with absolute value and composition percentage.

**Arguments:** dict with keys:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `field` | string | yes | Categorical field to group by |
| `measure` | string | yes | Numeric measure to aggregate |
| `asofDate` | string | yes | Date in `YYYY-MM-DD` format |
| `filters` | dict | no | Include filters |
| `exclusions` | dict | no | Exclude filters |
| `topN` | string | no | If set, returns only top N rows by value (e.g. `"5"`) |

**Returns:** list of dicts, sorted by value descending

```q
params:`field`measure`asofDate`filters!(
  "region"; "total_revenue"; "2026-02-26"; ()!());
.qryHandler.spot[params]
```

```
region  value     pct
----------------------
"AMER"  21134.34  0.473
"EMEA"  14431.35  0.323
"APAC"  9623.16   0.215
```

**Notes:**
- `pct` is each value divided by the total across all groups (after filters applied)
- Rows with null field values are excluded from results
- `topN` applies after sorting — returns highest N values

---

### `.qryHandler.trend` — Trend (Time Series)

Time series over a date window, broken down by a categorical field.

**Arguments:** dict with keys:

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `categoryField` | string | yes | Categorical field to break down by |
| `measure` | string | yes | Numeric measure to aggregate |
| `startDate` | string | yes | Window start in `YYYY-MM-DD` format (inclusive) |
| `endDate` | string | yes | Window end in `YYYY-MM-DD` format (inclusive) |
| `filters` | dict | no | Include filters |
| `exclusions` | dict | no | Exclude filters |

**Returns:** list of dicts, one per date × category combination

```q
params:`categoryField`measure`startDate`endDate`filters!(
  "region"; "total_revenue"; "2026-02-01"; "2026-02-28"; ()!());
.qryHandler.trend[params]
```

```
date         category  value
-----------------------------
"2026-02-02" "AMER"    19345.21
"2026-02-02" "APAC"    8102.44
"2026-02-02" "EMEA"    13987.62
"2026-02-03" "AMER"    20112.88
...
```

**Notes:**
- Dates in the returned `date` field are strings in `YYYY-MM-DD` format (dots replaced with dashes)
- Only dates with data in the HDB appear — missing dates are not zero-filled
- Filters apply to the underlying cache data before aggregation

---

## Filter Format

Filters and exclusions use the same dict format:

```q
/ Include only AMER and WidgetA:
filters:(enlist `region)!enlist ("AMER");                  / one field
filters:(`region`product)!(("AMER"); ("WidgetA";"WidgetB")) / two fields

/ Exclude APAC:
exclusions:(enlist `region)!enlist (enlist "APAC");

/ No filter:
()!()
```

Filter keys must be symbols (`` `region `` not `"region"`). Filter values are string lists.

---

## Error Handling

All handlers signal errors with `'` (signal). Wrap calls in trap if needed:

```q
result:@[.qryHandler.table; params; {[e] `error`msg!(1b; e)}];
if[`error in key result; / handle error /];
```

Common errors:

| Error | Cause |
|-------|-------|
| `"Missing params: field, measure, asofDate, prevDate"` | Required key absent from params dict |
| `"Invalid asofDate"` | Date string failed to parse — check `YYYY-MM-DD` format |
| `"Not cached: sales_by_region"` | Table not loaded in cache — server may need restart |
| `"Unknown field: xyz"` | Field not in catalog for this app |
| `"Field 'x' has role 'value' not 'categorical'"` | Wrong field used as grouping dimension |
