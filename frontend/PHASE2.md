# Phase 2 Roadmap

Phase 1 delivered: shared infrastructure (useDashboardState, AppShell, PresetBar, ControlSidebar), the Sales page as the first production app, mock-to-real backend swap pattern, URL state, preset system, and full documentation.

Phase 2 begins once the first real app port is complete and the infrastructure assumptions have been stress-tested against real data.

---

## Priority order

### 1. Port first real app *(in progress)*
The port will surface any gaps in the shared infrastructure that only appear with real data shapes — field types, date formats, filter cardinality, preset volume. Fix these before building new features on top.

**Watch for:**
- Fields that don't map cleanly to `categorical` / `value`
- Filters with high cardinality (100+ values) — KVDropdown may need virtualisation
- Init response latency — may need a loading skeleton in AppShell

---

### 2. Hierarchical data

**The problem:** Region is currently flat (`AMER`, `EMEA`, `APAC`). Real data is often a hierarchy: `Region → Country → Desk`. A flat table can't represent this.

**Backend (`lib/hierarchy.q` stub exists):**
- Implement `.hier.rollup` — aggregate a table at each level of a hierarchy
- Catalog format extension: add `parent_field` column to define the hierarchy relationship
- New query endpoint `/query/hierarchy` returning `{ level, path, value, children[] }`

**Frontend:**
- Expandable rows in `RegionSummaryGrid` — click a row to drill down one level
- Breadcrumb trail showing current drill path (e.g. `AMER > US > NY Desk`)
- Collapse back up by clicking any breadcrumb segment
- Hierarchy state is part of immediate state (auto-applies, no Apply button needed)
- URL serialises the drill path: `&drill=region:AMER/country:US`

**Not in scope:** Cross-hierarchy drill (e.g. drilling Region then Product simultaneously). That's a pivot problem — addressed separately below.

---

### 3. Click-to-filter

The dashboard is view-only. The one exception: clicking a dimension value in a table or chart adds it as a filter chip in the control bar — identical to selecting it manually from the KVDropdown.

**Rationale:** This is purely additive. It doesn't create a second interaction model — it's a shortcut to the existing filter system. It serialises to URL state naturally. It fits the immediate/deferred split: clicking a table row adds to `draft.filters`, which requires Apply.

**Implementation:**
- `RegionSummaryGrid` and `SpotBarChart` accept an optional `onDimensionClick: (key, value) => void` prop
- `Dashboard` wires this prop when provided by the page
- `SalesView` passes it through to `setDraft({ filters: [...draft.filters, { key, value }] })`
- Visual feedback: clicked row gets a brief highlight, corresponding chip appears in sidebar

**What it is not:** Cross-chart drill-down, master-detail navigation, or anything that changes the URL to a new page.

---

### 4. Rolling window overlay on trend charts

**The problem:** A raw daily trend line is noisy. Users want to see a smoothed overlay (e.g. 7-day or 30-day rolling average) alongside the raw series.

**Backend (`lib/rolling.q` stub exists):**
- Implement `.rolling.addRolling[tbl; col; window; fn; newCol]`
- Expose as an optional parameter on `/query/trend`: `{ "rolling": { "window": 7, "fn": "avg" } }`
- Backend returns both raw and rolled series in the same response

**Frontend:**
- `MultiLineTrendChart` renders the rolling series as a dashed line of the same colour
- `ControlSidebar` adds a rolling window toggle (off by default) under the `WithTrend` feature bundle
- Rolling window config is part of `WithTrend` immediate state — auto-applies

---

### 5. Export to CSV

Pure frontend — no backend changes needed. The data is already in memory in the dashboard.

**Implementation:**
- Each `DashboardCard` gets an export icon button in the header
- Clicking it serialises the card's current data to CSV and triggers a browser download
- Filename: `{field}-{mode}-{asofDate}.csv`
- Table cards export the full flat row data; chart cards export the time-series points

---

### 6. Auth and user-scoped presets

Currently presets are global — all users see the same presets. Once there are multiple users this breaks.

**Backend changes:**
- Init endpoint accepts a user identity (header or query param)
- Preset CRUD is scoped to `(app, user)` — "My Presets" are private, "Shared" are org-wide
- `isDefault` is per-user — each user has their own default preset

**Frontend changes:**
- `PresetSaveModal` groups already support "My Presets" vs "Shared" — no UI change needed
- The backend contract already has `group` as a free string — groups are server-controlled

**Note:** The frontend is already designed for this. The `group` field on presets anticipates the My/Shared distinction. This is entirely a backend implementation concern.

---

### 7. Pivot queries

**The problem:** Sometimes you want fields as columns rather than rows — e.g. Products as columns, Regions as rows, Revenue as cell values.

**Backend (`lib/pivot.q` stub exists):**
- Implement `.pivot.build[tbl; rowCol; colCol; measure; aggFn]`
- New query endpoint `/query/pivot`
- Catalog needs a way to express which field pairs support pivot

**Frontend:**
- New `PivotGrid` component — AG Grid with dynamic column generation
- New card type `dashboard-card--pivot` with orange-red accent
- `FieldPicker` extended with a `P` checkbox column alongside `T` and `C`
- Pivot state (`pivotRow`, `pivotCol`) stored in `SalesDraftState`

This is the most complex frontend item — dynamic columns require special AG Grid configuration and the column set changes with every query response.

---

### 8. Date range mode

**The problem:** Some apps compare a date range vs another range (e.g. Jan 2026 vs Jan 2025) rather than a single asof vs single prev date.

**Current design:** `WithComparison` has `prevDate: string | null` (single date). Extending to a range means adding `prevDateEnd` or switching to `{ from, to }` objects.

**Scope:**
- New feature bundle `WithDateRange` extending `BaseImmediateState`
- Date range pickers in `ControlSidebar` (two date inputs for each period — build as new `WithDateRange` sidebar controls)
- Pages opt in via `features: { dateRange: true }` in `useDashboardState`
- URL serialisation: `&asof_from=2026-01-01&asof_to=2026-01-31&prev_from=2025-01-01&prev_to=2025-01-31`

**Do not retrofit this onto Sales** — Sales is point-in-time. Build it for the first app that genuinely needs ranges.

---

### 9. Chart window → cache history control

**The question:** Should changing the chart window (30d / 60d / 90d / 1Y) control what history the backend cache holds, or just what the frontend requests from a fixed-size cache?

**Two options:**

**Option A — Fixed max cache, window is a query parameter (recommended for phase 2):**
The cache always holds 1Y of history on startup. The window just controls what date range the frontend requests in `/query/trend`. Zero backend change from current design. Simple.

**Option B — Cache size follows window:**
Window change triggers a cache reload. Adds latency on window change and requires a reload endpoint. Only worth doing if memory is a real constraint on the server.

**On the frontend (either option):**
Currently `chartWindow` is immediate state — change it, chart re-fetches with a different date range. If you also want the date pickers to reflect meaningful selectable dates for the chosen window, you have two sub-options:

1. **Frontend-only constraint** — constrain the date picker's selectable range based on `chartWindow` without any backend call. `30d` → only last 30 days selectable. Zero backend change.
2. **Re-fetch available dates** — window change triggers a lightweight `/api/sales/date-range?window=90d` call that returns the valid date bounds, which then constrains the date pickers. Requires `useDashboardState` to support a `refreshDates` action (currently has no concept of re-fetching init data mid-session).

**Recommendation:** Start with Option A + frontend-only constraint. Revisit if memory pressure or UX coherence becomes a real issue with real data.

---

### 10. User authentication and field-level access control

**Design principle: the frontend stays completely unaware of auth.** Permissions are enforced on the backend and expressed through what the init endpoint returns. No special-casing in React.

**How it works:**

The init endpoint accepts a user identity (request header — `X-User-ID` or a JWT). Based on that identity it returns a filtered `filterOptions` list — an AMER-only user receives only `{ key: "region", value: "AMER" }` in their filter options. The KVDropdown renders exactly what it receives, so restricted users simply never see options they can't use.

At query time, the backend applies a mandatory server-side whitelist before hitting KDB+ — regardless of what filters the request contains. This prevents users from crafting requests manually to bypass the UI restriction:

```q
/ Intersect request filters with what the user is allowed
/ If user has no restriction on a field, pass through unchanged
.auth.applyPerms:{[user; requestFilters]
  perms:.auth.perms[user];
  {[perm; field; reqVals]
    allowed:perm[field];
    $[0=count allowed; reqVals;                    / no restriction
      0=count reqVals; allowed;                    / no request filter — apply restriction
      reqVals inter allowed]                       / intersect both
  }[perms;;] ./: flip (key; value) @\: requestFilters
 }
```

Presets are also scoped — the backend only returns presets the user is allowed to access.

**Where permissions live — `apps/sales/permissions.csv`:**

Same pattern as the catalog CSV. Auto-loaded at server startup. No new infrastructure.

```
user,field,allowed_values
alice,region,AMER
bob,region,AMER:EMEA
carol,product,WidgetB
```

`allowed_values` is a colon-delimited list. Empty = no restriction (full access). A `groups` extension (user belongs to group, group has permissions) can be layered on top of the same file format later.

**What changes:**

| Layer | Change |
|---|---|
| Backend | Load `permissions.csv` at startup; filter `filterOptions` in init; apply `.auth.applyPerms` in all query handlers before KDB+ execution |
| Frontend | **Zero changes** — the KVDropdown, tables, and charts already render only what the server returns |
| Backend contract | Init endpoint accepts `X-User-ID` header; document mandatory server-side enforcement |

**Phase 2 implementation order:** Add permissions CSV loading first, then enforce in init (filterOptions filtering), then enforce in query handlers. Test with the mock by having different init responses simulate different users.


All of these exist as stub files in `lib/` from the original infrastructure build. Phase 2 is real implementations:

| File | Status | Phase 2 work |
|---|---|---|
| `lib/hierarchy.q` | Stub | Full implementation + catalog schema extension |
| `lib/rolling.q` | Stub | Implement all window functions (avg, sum, max, min, std) |
| `lib/pivot.q` | Stub | Implement `.pivot.build` + HTTP endpoint |
| `lib/temporal_join.q` | Stub | Implement as-of join and window join wrappers |
| `lib/filters.q` | Stub | Stress-test with high-cardinality filter sets |
| `lib/comparison.q` | Partial | Extend to support date range comparison |
| `lib/dates.q` | Partial | Add quarter/month boundary helpers |

---

## Deferred infrastructure items

| Item | Notes |
|---|---|
| `monitoring/monitoring.q` | Health check registry stub — implement real checks (memory, query latency, partition freshness) |
| `maintenance/retention_manager.q` | Partition retention policy — implement dry-run + enforce modes |
| KVDropdown virtualisation | Only needed if filter options exceed ~200 items |
| Loading skeleton in AppShell | Only needed if init response latency becomes noticeable |

---

## What phase 2 is not

- **Real-time / streaming data** — the architecture is partitioned HDB + daily ingestion. Streaming would require a separate tick plant and a websocket layer. Not in scope.
- **Mobile layout** — the 3-column dashboard assumes a wide screen. A responsive layout for mobile is a separate concern.
- **Cross-app views** — combining data from two apps in one dashboard. The server-per-app design makes this complex. Not in scope.
