# Backend Contract

Everything the frontend currently mocks that must be replaced with a real implementation.  
Each section maps directly to a function in `src/pages/SalesView/salesService.ts`.

The mock implementation lives in `mockService.ts` — read it alongside this document to see exactly what data shapes are expected.

---

## Base URL

Configured in `src/services/dataService.ts`:

```ts
const BASE_URL = 'http://localhost:8080';  // KDB+ HTTP server
```

All endpoints are relative to this base. The fetch helpers `kdbGet` and `kdbPost` add JSON headers and throw on non-2xx responses.

---

## Endpoint summary

| Method | Path | Description |
|---|---|---|
| GET | `/api/sales/init` | Page bootstrap — dates, catalog, filter options, presets |
| POST | `/api/sales/query/table` | Movement table (asof vs prev comparison) |
| POST | `/api/sales/query/spot` | Spot view (single-date bar chart) |
| POST | `/api/sales/query/trend` | Trend over time (multi-line chart) |
| POST | `/api/sales/presets` | Save new preset |
| POST | `/api/sales/presets/:id/delete` | Delete a preset |
| POST | `/api/sales/presets/:id/default` | Set a preset as default |

---

## GET /api/sales/init

Called once on page load. Returns everything needed to render the page before any user interaction.

### Response

```json
{
  "latestAsofDate":  "2026-02-26",
  "defaultPrevDate": "2026-01-27",
  "catalogFields": [
    { "field": "region",         "label": "Region",         "fieldType": "categorical" },
    { "field": "product",        "label": "Product",        "fieldType": "categorical" },
    { "field": "total_quantity", "label": "Total Quantity", "fieldType": "value" },
    { "field": "total_revenue",  "label": "Total Revenue",  "fieldType": "value" }
  ],
  "filterOptions": [
    { "key": "region",  "value": "AMER" },
    { "key": "region",  "value": "APAC" },
    { "key": "region",  "value": "EMEA" },
    { "key": "product", "value": "WidgetA" },
    { "key": "product", "value": "WidgetB" },
    { "key": "product", "value": "WidgetC" }
  ],
  "presets": [ /* see Preset shape below */ ]
}
```

### Field types
- `categorical` — rendered as a Group By field (drag-and-drop, table/chart checkboxes)
- `value` — rendered as a Measure option (radio button)

### Notes
- `latestAsofDate` should be the most recent business day with data — used as the default ASOF date
- `defaultPrevDate` should be one month prior — used as the default PREV date
- `filterOptions` is a flat list of all `{ key, value }` pairs available for filtering/exclusion — the frontend groups them by key in the dropdown UI
- `presets` are returned **server-ordered** — the order field determines chip order in the PresetBar. The backend controls preset ordering.

---

## Preset shape

Used in init response and all preset CRUD responses.

```json
{
  "id":        "preset-uuid-1",
  "name":      "Default View",
  "group":     "My Presets",
  "isDefault": true,
  "order":     0,
  "state": {
    "filters":      [],
    "exclusions":   [],
    "measure":      "total_quantity",
    "fieldConfigs": [
      { "field": "region",  "showTable": true, "showChart": true },
      { "field": "product", "showTable": true, "showChart": true }
    ]
  }
}
```

### Important
- `state` is the deferred state only — **never contains dates**
- Only one preset should have `isDefault: true` at any time
- `group` is a free string — the frontend groups chips by this value in the overflow dropdown
- `order` determines display order in the PresetBar — the backend is the source of truth

---

## POST /api/sales/query/table

Returns movement data (asof vs prev comparison) for one dimension field.

### Request body

```json
{
  "asofDate":     "2026-02-26",
  "prevDate":     "2026-01-27",
  "measure":      "total_revenue",
  "field":        "region",
  "filters":      { "region": ["AMER", "EMEA"] },
  "exclusions":   { "product": ["WidgetB"] }
}
```

### Response

Array of `FlatRow` — one row per dimension value:

```json
[
  {
    "region":    "AMER",
    "asofValue": 22145.80,
    "prevValue": 20300.00,
    "change":    1845.80,
    "changePct": 0.0909
  },
  {
    "region":    "EMEA",
    "asofValue": 17823.50,
    "prevValue": 18100.00,
    "change":    -276.50,
    "changePct": -0.0153
  }
]
```

### Notes
- The dimension key in each row must match `field` (e.g. `"region"` or `"product"`)
- `changePct` is a decimal fraction, not a percentage — `0.0909` = 9.09%
- Filters and exclusions only apply to rows that **have** the filtered key — a product query should ignore region filters
- Return empty array `[]` if no data for the date range

---

## POST /api/sales/query/spot

Returns spot data (single-date snapshot) for one dimension field, used in the bar chart view.

### Request body

```json
{
  "asofDate":   "2026-02-26",
  "measure":    "total_revenue",
  "field":      "product",
  "filters":    {},
  "exclusions": {}
}
```

### Response

Array of `SpotRow` — one row per dimension value, sorted descending by value:

```json
[
  { "product": "WidgetA", "value": 18342.20, "pct": 0.4104 },
  { "product": "WidgetB", "value": 14823.50, "pct": 0.3317 },
  { "product": "WidgetC", "value": 12023.15, "pct": 0.2591 }
]
```

### Notes
- `pct` is each row's share of the total — must sum to 1.0 across all rows
- The dimension key in each row must match `field`
- Sort descending by value — the bar chart renders top-to-bottom

---

## POST /api/sales/query/trend

Returns time-series data for one dimension field, used in the multi-line trend chart.

### Request body

```json
{
  "asofDate":    "2026-02-26",
  "chartWindow": "30d",
  "measure":     "total_revenue",
  "field":       "region",
  "filters":     {},
  "exclusions":  {}
}
```

`chartWindow` values: `"30d"` | `"60d"` | `"90d"` | `"1Y"`

### Response

Flat array of `TrendByDimensionPoint` — one entry per (date × category) combination:

```json
[
  { "date": "2026-01-27", "category": "AMER", "value": 21800.00 },
  { "date": "2026-01-27", "category": "EMEA", "value": 17500.00 },
  { "date": "2026-01-27", "category": "APAC", "value": 9800.00  },
  { "date": "2026-01-28", "category": "AMER", "value": 21950.00 },
  ...
]
```

### Notes
- `date` format: `"YYYY-MM-DD"`
- The frontend groups by `category` to build one line per dimension value
- Return business days only (no weekends/holidays) from `asofDate - window` to `asofDate` inclusive
- `chartWindow` to date range: `30d` = 30 calendar days back, `60d` = 60, `90d` = 90, `1Y` = 365

---

## POST /api/sales/presets

Save a new preset. The backend assigns `id` and `order`.

### Request body

```json
{
  "name":  "EMEA Q1 View",
  "group": "Shared",
  "state": {
    "filters":      [{ "key": "region", "value": "EMEA" }],
    "exclusions":   [],
    "measure":      "total_revenue",
    "fieldConfigs": [
      { "field": "region",  "showTable": true, "showChart": true },
      { "field": "product", "showTable": false, "showChart": true }
    ]
  }
}
```

### Response

The saved preset with server-assigned `id` and `order`:

```json
{
  "id":        "new-uuid",
  "name":      "EMEA Q1 View",
  "group":     "Shared",
  "isDefault": false,
  "order":     3,
  "state":     { /* echoed back */ }
}
```

---

## POST /api/sales/presets/:id/delete

Delete a preset by ID.

### Request body
Empty: `{}`

### Response
`200 OK` with empty body or `{ "ok": true }`.

---

## POST /api/sales/presets/:id/default

Mark a preset as the default. Clears `isDefault` on all other presets for this user.

### Request body
Empty: `{}`

### Response
`200 OK` with empty body or `{ "ok": true }`.

---

## Error handling

All endpoints should return standard HTTP error codes. The frontend surface:
- Network errors and non-2xx responses are caught and displayed as an error state
- Empty arrays `[]` are valid — the dashboard renders an empty state rather than an error
- `null` fields (e.g. `asofDate: null`) cause queries to short-circuit and return `[]`

---

## Adding a new page's endpoints

For each new page (e.g. Risk), follow the same pattern:

```
GET  /api/risk/init
POST /api/risk/query/...      (one endpoint per query type the page needs)
POST /api/risk/presets
POST /api/risk/presets/:id/delete
POST /api/risk/presets/:id/default
```

The init response shape is always the same — `latestAsofDate`, `defaultPrevDate`, `catalogFields`, `filterOptions`, `presets`. Query endpoints are page-specific.
