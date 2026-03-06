# Adding a New Page

Step-by-step guide for building a new dashboard page on the shared infrastructure.  
This guide uses a hypothetical **Risk** page as the worked example.

---

## Overview

Building a new page requires:
1. Define your types (`TImmediate`, `TDeferred`)
2. Create your service files (mock + real)
3. Wire `useDashboardState`
4. Compose the page — sidebar children, dashboard content

You write zero state management logic. All of that lives in `useDashboardState`.

---

## Step 1 — Define your types

Create `src/types/risk.ts`:

```ts
import { BaseImmediateState, KVOption, FieldConfig, Preset, CatalogField } from './index';

// ── Immediate state (auto-apply on change) ─────────────────────────────────
// Risk has no comparison or trend features — just asofDate
export interface RiskImmediateState extends BaseImmediateState {}

// ── Deferred state (Apply button gates this) ───────────────────────────────
export interface RiskDraftState {
  filters:  KVOption[];
  scenario: string | null;   // page-specific control
}

// ── Preset (deferred only — never include dates) ───────────────────────────
export type RiskPresetState = RiskDraftState;
export type RiskPreset      = Preset<RiskPresetState>;

// ── Init response ──────────────────────────────────────────────────────────
export interface RiskInitResponse {
  latestAsofDate: string;
  scenarios:      string[];
  filterOptions:  KVOption[];
  presets:        RiskPreset[];
}

// ── Defaults ───────────────────────────────────────────────────────────────
export const DEFAULT_RISK_IMMEDIATE: RiskImmediateState = {
  asofDate: null,
};

export const DEFAULT_RISK_DRAFT: RiskDraftState = {
  filters:  [],
  scenario: null,
};
```

**Key rules:**
- `TImmediate` always extends `BaseImmediateState` (gives you `asofDate`)
- Opt into feature bundles with `WithComparison` and/or `WithTrend` if needed
- `TDeferred` (preset state) must **never** include dates
- Always export defaults — the hook needs them before init completes

---

## Step 2 — Create the mock service

Create `src/pages/RiskView/mockService.ts`:

```ts
import { QueryParams } from '../../types';
import { RiskInitResponse, RiskPreset, RiskPresetState } from '../../types/risk';
import { InitData } from '../../hooks/useDashboardState';

const delay = (ms = 300) => new Promise<void>(res => setTimeout(res, ms));

// ── Mock presets ────────────────────────────────────────────────────────────
const MOCK_PRESETS: RiskPreset[] = [
  {
    id: 'risk-preset-1',
    name: 'Base Scenario',
    group: 'My Presets',
    isDefault: true,
    order: 0,
    state: { filters: [], scenario: 'base' },
  },
];

// ── Init ────────────────────────────────────────────────────────────────────
export const getInitData = async (): Promise<InitData<RiskPresetState>> => {
  await delay(200);
  return {
    latestAsofDate:  '2026-02-26',
    defaultPrevDate: '2026-01-27',   // required by InitData shape even if unused
    catalogFields:   [],
    filterOptions:   [],
    presets:         MOCK_PRESETS,
  };
};

// ── Queries ─────────────────────────────────────────────────────────────────
export const getRiskData = async (params: QueryParams): Promise<unknown[]> => {
  await delay(350);
  return [];  // replace with actual mock data
};

// ── Preset CRUD ─────────────────────────────────────────────────────────────
export const savePreset   = async (state: RiskPresetState, name: string, group: string): Promise<RiskPreset> => ({
  id: crypto.randomUUID(), name, group, isDefault: false, order: 99, state,
});
export const deletePreset    = async (_id: string): Promise<void> => {};
export const setDefaultPreset = async (_id: string): Promise<void> => {};
```

---

## Step 3 — Create the real service

Create `src/pages/RiskView/salesService.ts` (same signatures, real fetch calls):

```ts
import { QueryParams } from '../../types';
import { RiskPreset, RiskPresetState } from '../../types/risk';
import { kdbGet, kdbPost } from '../../services/dataService';
import { InitData } from '../../hooks/useDashboardState';

export const getInitData       = (): Promise<InitData<RiskPresetState>> => kdbGet('/api/risk/init');
export const getRiskData       = (params: QueryParams): Promise<unknown[]> => kdbPost('/api/risk/query', params);
export const savePreset        = (state: RiskPresetState, name: string, group: string): Promise<RiskPreset> =>
  kdbPost('/api/risk/presets', { state, name, group });
export const deletePreset      = (id: string): Promise<void> => kdbPost(`/api/risk/presets/${id}/delete`, {});
export const setDefaultPreset  = (id: string): Promise<void> => kdbPost(`/api/risk/presets/${id}/default`, {});
```

---

## Step 4 — Define buildQueryParams

This is a pure function that maps your page's state into the `QueryParams` shape the backend expects.

```ts
// In RiskView/index.tsx
const buildQueryParams = (imm: RiskImmediateState, draft: RiskDraftState): QueryParams => {
  const collapse = (pairs: KVOption[]): Record<string, string[]> =>
    pairs.reduce((acc, { key, value }) => {
      acc[key] = [...(acc[key] ?? []), value];
      return acc;
    }, {} as Record<string, string[]>);

  return {
    asofDate:     imm.asofDate,
    measure:      null,
    fieldConfigs: [],
    filters:      collapse(draft.filters),
    exclusions:   {},
    // pass scenario as a filter or add it to QueryParams if needed
  };
};
```

No `useCallback` needed — `useDashboardState` stores it in a ref internally.

---

## Step 5 — Wire useDashboardState

```ts
// src/pages/RiskView/index.tsx
import { useDashboardState } from '../../hooks/useDashboardState';
import { RiskImmediateState, RiskDraftState, DEFAULT_RISK_IMMEDIATE, DEFAULT_RISK_DRAFT } from '../../types/risk';
import { getInitData, savePreset, deletePreset, setDefaultPreset } from './mockService';

const state = useDashboardState<RiskImmediateState, RiskDraftState>({
  fetchInitData:    getInitData,
  savePresetFn:     savePreset,
  deletePresetFn:   deletePreset,
  setDefaultFn:     setDefaultPreset,
  defaultImmediate: DEFAULT_RISK_IMMEDIATE,
  defaultDeferred:  DEFAULT_RISK_DRAFT,
  urlSync:          true,
  buildQueryParams,
});
```

The sidebar opts into features purely through prop presence — pass `prevDate` + `onPrevChange` to enable comparison mode, pass `chartWindow` + `onChartWindowChange` to enable the trend window selector. No hook config needed.

---

## Step 6 — Compose the page

```tsx
const RiskView = () => {
  const [collapsed, setCollapsed] = useState(false);
  const { immediate, draft, appliedParams, presets, ... } = state;

  return (
    <AppShell
      header={<header className="app-header">...</header>}
      commandZone={
        <>
          <PresetBar
            presets={presets}
            activePresetId={activePresetId}
            isDirty={isDirty}
            onLoadPreset={p => loadPreset(p as never)}
            onRevertPreset={revertPreset}
            onSavePreset={handleSavePreset}
          />
          {appliedParams && <AppliedParamsBar params={appliedParams} catalogFields={[]} />}
        </>
      }
      sidebar={
        <ControlSidebar
          asofDate={immediate.asofDate}
          onAsofChange={v => setImmediate({ asofDate: v })}
          onApply={handleApply}
          collapsed={collapsed}
          onToggleCollapse={() => setCollapsed(c => !c)}
          // No prevDate, mode, or chartWindow props = no comparison/trend UI
        >
          {/* Page-specific deferred controls */}
          {/* Page-specific deferred controls go here — e.g. a native <select> or KVDropdown */}
        </ControlSidebar>
      }
    >
      {appliedParams ? <RiskDashboard params={appliedParams} /> : null}
    </AppShell>
  );
};
```

---

## Step 7 — Register the route

In `src/App.tsx`, add your page to the router:

```tsx
import RiskView from './pages/RiskView';

// In the router:
<Route path="/risk" element={<RiskView />} />
```

---

## Feature opt-in summary

| Feature | Type extension | Props to pass to ControlSidebar |
|---|---|---|
| Comparison (prevDate + mode) | `extends WithComparison` | `prevDate`, `onPrevChange`, `mode`, `onModeChange` |
| Trend window | `extends WithTrend` | `chartWindow`, `onChartWindowChange` |
| Both | `extends WithComparison, WithTrend` | All of the above |
| Neither | Just `extends BaseImmediateState` | None |

---

## Checklist

- [ ] `src/types/yourPage.ts` — TImmediate, TDeferred, Preset type, InitResponse, defaults
- [ ] `src/pages/YourView/mockService.ts` — getInitData + all query functions + preset CRUD
- [ ] `src/pages/YourView/salesService.ts` — identical signatures, real fetch calls
- [ ] `buildQueryParams` defined in page (no useCallback needed)
- [ ] `useDashboardState` wired with correct feature flags
- [ ] `AppShell` composed with header, commandZone, sidebar, children
- [ ] Route registered in `App.tsx`
- [ ] Backend endpoints implemented per `BACKEND_CONTRACT.md`
