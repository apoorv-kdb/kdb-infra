# Catalog Reference

The catalog CSV is the single source of truth for every field an application cares about. It drives ingestion (column mapping, type casting, validation) and field metadata (labels, formats, which fields are exposed). No code changes are needed to accept a new column alias or add a new field — edit the catalog and restart.

---

## File Location and Naming

```
config/catalog_<app>.csv
```

One catalog file per application. The app name in the filename must match the `app` column values inside the file and the app name passed to `.catalog.load`.

---

## Column Reference

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `app` | string | yes | Application name. Must match the name passed to `.catalog.load`. |
| `table` | string | yes | Canonical table name. Must follow `{domain}_{name}` naming convention (e.g. `sales_by_region`). |
| `field` | string | yes | Canonical field name used throughout the system (e.g. `total_revenue`). |
| `label` | string | yes | Display label shown in frontend field pickers and column headers. |
| `type` | string | yes | Target type after casting. See type values below. |
| `role` | string | yes | Analytical role of the field. See role values below. |
| `format` | string | no | Display format hint for frontends. See format values below. |
| `enabled` | boolean | yes | `1` = field is visible to frontends via `.catHandler.fields`. `0` = ingested and validated but hidden. |
| `source_field` | string | no | Source column name in the raw CSV. Leave blank when the source column name matches the canonical field name exactly. |
| `date_format` | string | no | Explicit date format for this source. See date format values below. Leave blank to auto-detect. |

---

## Type Values

| Value | Cast applied | Use for |
|-------|-------------|---------|
| `symbol` | `` `$col `` | Categories, codes, identifiers |
| `float` | `"F"$col` | Monetary values, rates, ratios |
| `long` | `"J"$col` | Counts, quantities, integer metrics |
| `int` | `"I"$col` | Smaller integers where long is wasteful |
| `date` | `"D"$col` | Date columns (expects `YYYY-MM-DD` or `YYYY.MM.DD`) |
| `timestamp` | `"P"$col` | Datetime columns |

---

## Role Values

| Value | Meaning | Used for |
|-------|---------|---------|
| `categorical` | Grouping dimension | Field picker dimensions, filter/exclusion keys |
| `value` | Numeric measure | Field picker measures, aggregation target |
| `temporal` | Date/time column | Internal use — date filtering in query handlers |

`temporal` fields are never shown in the frontend field picker regardless of `enabled`. They are required for the query handlers to filter by date.

---

## Format Values

Format is a hint to the frontend for display formatting. It does not affect how data is stored or computed.

| Value | Meaning |
|-------|---------|
| `currency` | Format as monetary value (e.g. `$1,234.56`) |
| `integer` | Format as integer with thousands separator (e.g. `1,234`) |
| `percent` | Format as percentage (e.g. `12.3%`) |
| `date` | Format as readable date string |
| *(blank)* | No specific formatting — display as-is |

---

## Date Format Values

Applies only to fields with `type=date`. Declared per catalog row so different sources feeding the same field can use different formats.

| Value | Format | Example |
|-------|--------|---------|
| *(blank)* | Auto-detect | Tries `YYYYMMDD`, then `DD/MM/YYYY`, then passes through for `"D"$` to handle `YYYY-MM-DD` and `YYYY.MM.DD` |
| `YYYYMMDD` | 8 digits, no separator | `20260127` |
| `DDMMYYYY` | Day-first, no separator | `27012026` |
| `MMDDYYYY` | Month-first, no separator | `01272026` |

`DD/MM/YYYY` (slash-separated, day-first) is handled by auto-detect and does not need an explicit format value.

If two source aliases for the same canonical field have different `date_format` values, the last row in the catalog wins. In practice, if two sources represent the same field, they should use the same format — if not, map them to separate canonical fields and merge in `data_refresh.q`.

---

## Source Field Mapping

The `source_field` column handles the reality that different upstream systems use different column names for the same data. Multiple rows for the same `field` = multiple accepted source aliases.

**Example:** three different systems all feed `region` data under different names:

```csv
app,table,field,label,type,role,format,enabled,source_field
sales,sales_transactions,region,Region,symbol,categorical,,0,region
sales,sales_transactions,region,Region,symbol,categorical,,0,geo
sales,sales_transactions,region,Region,symbol,categorical,,0,GEO_REGION
```

All three source column names map to canonical `region`. Only one needs to be present in any given file. If multiple are present, explicit mappings take priority over identity mappings.

**Leave `source_field` blank** when the source column name already matches the canonical field name. The catalog builds an identity mapping automatically.

---

## The enabled Flag

`enabled=1` means the field is returned by `.catHandler.fields` and visible in frontend field pickers.

`enabled=0` means the field is used for ingestion (validated and cast) but never surfaced to consumers.

The pattern is to mark raw transaction table fields as `enabled=0` and aggregated summary table fields as `enabled=1`. This lets you ingest and validate the raw source data without cluttering the analytical interface with fields that only exist at the transaction level.

```csv
/ Raw table — ingested but hidden from UI
sales,sales_transactions,revenue,Revenue,float,value,currency,0,revenue

/ Aggregated table — visible in UI
sales,sales_by_region,total_revenue,Total Revenue,float,value,currency,1,
```

---

## Worked Example: Full Sales Catalog

```csv
app,table,field,label,type,role,format,enabled,source_field
sales,sales_transactions,date,Date,date,temporal,,0,date
sales,sales_transactions,date,Date,date,temporal,,0,Date
sales,sales_transactions,date,Date,date,temporal,,0,trade_date
sales,sales_transactions,region,Region,symbol,categorical,,0,region
sales,sales_transactions,region,Region,symbol,categorical,,0,Region
sales,sales_transactions,region,Region,symbol,categorical,,0,geo
sales,sales_transactions,product,Product,symbol,categorical,,0,product
sales,sales_transactions,product,Product,symbol,categorical,,0,Product
sales,sales_transactions,product,Product,symbol,categorical,,0,instrument
sales,sales_transactions,quantity,Quantity,long,value,integer,0,quantity
sales,sales_transactions,quantity,Quantity,long,value,integer,0,qty
sales,sales_transactions,revenue,Revenue,float,value,currency,0,revenue
sales,sales_transactions,revenue,Revenue,float,value,currency,0,Rev
sales,sales_transactions,revenue,Revenue,float,value,currency,0,revenue_usd
sales,sales_by_region,date,Date,date,temporal,,1,
sales,sales_by_region,region,Region,symbol,categorical,,1,
sales,sales_by_region,product,Product,symbol,categorical,,1,
sales,sales_by_region,total_revenue,Total Revenue,float,value,currency,1,
sales,sales_by_region,total_quantity,Total Quantity,long,value,integer,1,
```

Note that `sales_transactions` has `enabled=0` throughout — it is the raw source, processed but not exposed. `sales_by_region` has `enabled=1` — it is the aggregated table the frontend queries.

---

## Common Mistakes

**Missing `temporal` field** — every table that is queried by date must have a `date` field with `role=temporal`. The query handlers filter on `date` — if it's absent from the catalog, it won't be cast correctly, and date filters will silently fail or error.

**Aggregated table not in catalog** — if `data_refresh.q` writes `sales_by_region` but the catalog only lists `sales_transactions` rows for the app, `.cache.loadOne` will succeed but `.catHandler.fields` will return no fields. Both the raw and aggregated tables need catalog entries.

**Source field blank on unmapped column** — leaving `source_field` blank means the system expects the source CSV column to already be named identically to the canonical field. If your source uses a different name and you leave `source_field` blank, the column will be silently dropped. If data is missing after ingestion, check the source map.

**Wrong date format** — if dates are casting to null, either set `date_format` explicitly in the catalog for the source row, or check that the source format is one of the auto-detected ones (`YYYYMMDD`, `DD/MM/YYYY`, `YYYY-MM-DD`, `YYYY.MM.DD`). `MM/DD/YYYY` US ordering requires explicit `date_format=MMDDYYYY`.
