# Architecture & Philosophy

This document explains how the frontend is structured and why. Read this before building a new page or touching shared infrastructure.

---

## Core principle: infrastructure vs composition

The system is split into two layers:

**Infrastructure** — written once, never touched per page:
- `useDashboardState` hook — all state logic
- `AppShell` — layout slots
- `ControlSidebar` — sidebar chrome
- `PresetBar` / `AppliedParamsBar` — command zone
- `urlSerializer` — URL state
- `dataService` — HTTP fetch helpers

**Composition** — written per page, completely page-specific:
- Types (`TImmediate`, `TDeferred`)
- Service files (`mockService.ts`, `salesService.ts`)
- Sidebar children (dropdowns, pickers)
- Dashboard layout and data cards

A new page wires together infrastructure via composition. It never modifies infrastructure.

---

## State architecture: immediate vs deferred

Every page has two distinct parameter buckets:

### Immediate state
Changes apply to the dashboard **instantly**, without pressing Apply.

```ts
interface SalesImmediateState extends BaseImmediateState, WithComparison, WithTrend {
  // asofDate    — inherited from BaseImmediateState
  // prevDate    — inherited from WithComparison
  // mode        — inherited from WithComparison  ('movement' | 'spot')
  // chartWindow — inherited from WithTrend       ('30d' | '60d' | '90d' | '1Y')
}
```

These are single-value picks — exploring dates or switching mode should feel instantaneous.

### Deferred state (draft)
Changes are **staged** until the user clicks Apply.

```ts
interface SalesDraftState {
  filters:      KVOption[];    // additive multi-select
  exclusions:   KVOption[];    // additive multi-select
  fieldConfigs: FieldConfig[]; // controls which panels render
  measure:      string | null; // which metric to display
}
```

These are compositional — building up a set of filters should not trigger a fetch on every click.

### Why this split?

- Dates and mode are stateless exploratory choices. The user expects clicking them to do something.
- Filters and field configs are compositional. The user expects to build them up before committing.
- This split maps naturally to the UI: the sidebar has an Apply button for deferred state, but date pickers and mode toggles act immediately.

---

## Feature bundles

Pages opt into optional feature bundles by extending the base immediate state:

```ts
interface BaseImmediateState { asofDate: string | null; }     // always present
interface WithComparison     { prevDate: string | null; mode: AnalyticalMode; }
interface WithTrend          { chartWindow: '30d' | '60d' | '90d' | '1Y'; }
```

`ControlSidebar` renders features based on prop presence:
- Pass `prevDate` + `onPrevChange` → prev date picker appears
- Pass `mode` + `onModeChange` → mode toggle appears
- Pass `chartWindow` + `onChartWindowChange` → window buttons appear
- Pass none → sidebar shows only ASOF date

A Risk page with no comparison or trend feature would pass none of these optional props.

---

## Preset system

### What presets store
Presets capture **how to look at data**, not **when**. They store deferred state only:

```ts
type SalesPresetState = SalesDraftState;  // filters + exclusions + fieldConfigs + measure
```

Dates are never stored in presets. This is intentional — a preset named "EMEA Focus" should work for any asof date.

### How presets work
1. Loading a preset: sets `draft` = preset state, stores a snapshot, auto-applies
2. Dirty tracking: `isDirty = JSON.stringify(draft) !== JSON.stringify(snapshot)`
3. Revert: restores snapshot, auto-applies — no Apply button needed
4. Presets are **server-managed** — ordering, groups, and the default are controlled by the backend

### What the dirty indicator means
When a preset chip shows `●`, the current draft differs from when that preset was last loaded or saved. The `↺` icon reverts to the clean snapshot.

---

## URL state

Applied state is serialized to the URL on every change via `replaceState` (no history pollution).

```
?asof=2026-02-26&prev=2026-01-27&mode=movement&window=30d
&measure=total_quantity&fields=region:TC,product:T
&f=region:AMER&x=product:WidgetB
```

Field encoding: `region:TC` = table + chart, `region:T` = table only, `region:C` = chart only.  
Filter/exclusion encoding: `f=region:AMER,region:EMEA` = `{ region: ['AMER', 'EMEA'] }`.

On page load, initialization priority is:
1. URL params (if `asofDate` present) → build state from URL, skip preset
2. Default preset → load and auto-apply
3. Server defaults from init response

---

## useDashboardState hook

This hook owns all state for a page. It is the only place state transitions are defined.

```ts
const state = useDashboardState<TImmediate, TDeferred>({
  fetchInitData,       // () => Promise<InitData<TDeferred>>
  savePresetFn,        // (state, name, group) => Promise<Preset>
  deletePresetFn,      // (id) => Promise<void>
  setDefaultFn,        // (id) => Promise<void>
  defaultImmediate,    // TImmediate — used before init loads
  defaultDeferred,     // TDeferred  — used if no preset and no URL
  features,            // { comparison: bool, trend: bool }
  urlSync,             // whether to write state to URL
  buildQueryParams,    // (TImmediate, TDeferred) => QueryParams
});
```

`buildQueryParams` is page-defined but stored in a ref inside the hook — so it is always current without causing re-renders. This is why it does not need `useCallback` at the call site.

### What the hook returns

| Field | Type | Description |
|---|---|---|
| `immediate` | `TImmediate` | Current immediate state (reflects UI instantly) |
| `draft` | `TDeferred` | Current staged draft (pending Apply) |
| `appliedParams` | `QueryParams \| null` | What the dashboard is currently rendering |
| `activePresetId` | `string \| null` | Which preset is loaded |
| `isDirty` | `boolean` | Whether draft differs from preset snapshot |
| `setImmediate` | `(patch) => void` | Update immediate + auto-apply |
| `setDraft` | `(patch) => void` | Stage a draft change (no apply) |
| `handleApply` | `() => void` | Flush draft to appliedParams |
| `loadPreset` | `(preset) => void` | Load preset + auto-apply |
| `revertPreset` | `() => void` | Restore snapshot + auto-apply |

---

## Command zone

The dark band between the header and dashboard contains two components:

```
┌─────────────────────────────────────────────────────────┐  ← header ($slate-900)
├─────────────────────────────────────────────────────────┤
│  [My Presets] Default View ●  Region Only  AMER Focus  +│  ← PresetBar
├ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│  ← divider
│  ASOF 26 Feb 26  PREV 27 Jan 26  MODE movement  …       │  ← AppliedParamsBar
├─────────────────────────────────────────────────────────┤  ← dashboard ($slate-50)
```

The command zone (`$slate-700`) is visually between the header (darkest) and dashboard (lightest). It always reflects **applied** state — what is currently rendered — not the staged draft.

---

## Design tokens

All visual constants live in `src/styles/_variables.scss`. Never hard-code colors or spacing in component files. The key tokens:

```scss
// Backgrounds — visual hierarchy from dark to light
--color-bg-command-zone   // $slate-700 — command zone
--color-bg-sidebar        // $slate-100 — sidebar
--color-bg-app            // $slate-50  — dashboard
--color-bg-surface        // #FFFFFF    — cards

// Command zone (inverted — light text on dark bg)
--color-command-text
--color-command-text-muted
--color-command-chip-bg
--color-command-chip-border
--color-command-divider

// Card accent colors
--color-card-table        // blue  — movement/table cards
--color-card-spot         // teal  — spot cards
--color-card-chart        // amber — trend chart cards
```

---

## What to touch vs what not to touch

### Never modify (shared infrastructure)
- `src/hooks/useDashboardState.ts`
- `src/services/urlSerializer.ts`
- `src/components/AppShell/`
- `src/components/PresetBar/`
- `src/components/AppliedParamsBar/`
- `src/styles/_variables.scss` *(extend, don't change existing tokens)*

### Extend carefully (shared components with page-specific slots)
- `src/components/ControlSidebar/` — add optional props only, keep existing ones
- `src/components/Dashboard/` — add card types, don't change fetch orchestration
- `src/types/index.ts` — add types, don't remove or rename existing ones

### Own completely (page-specific, safe to modify freely)
- Everything under `src/pages/YourPage/`
- `src/types/yourPage.ts`

---

## Filters behave at the dimension level

When filters are applied, they only filter rows that **have** the filtered field. A `region:AMER` filter does not suppress product rows — product rows don't have a `region` field, so the filter is not applied to them.

This is intentional: filters narrow the data within a dimension, not across dimensions.
