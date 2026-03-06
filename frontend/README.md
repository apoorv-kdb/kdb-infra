# KDB Analytics — Frontend

React/TypeScript dashboard frontend for the KDB+ analytics infrastructure.  
Currently runs on **mock data**. Swap one import to connect the real backend.

---

## Stack

| Layer | Technology |
|---|---|
| Framework | React 18 + TypeScript |
| Build | Vite |
| Styling | SCSS (CSS custom properties for theming) |
| Charts | Highcharts + highcharts-react-official |
| Tables | AG Grid Community |
| Icons | FontAwesome |

---

## Getting started

```bash
cd frontend
npm install
npm run dev        # http://localhost:5173
npm run build      # type-check + production bundle
```

---

## Connecting the real backend

The app ships with a mock service that mirrors the exact same API contract as the real backend.  
To connect real data, change **one line** in `src/pages/SalesView/index.tsx`:

```ts
// Currently (mock):
} from './mockService';

// Switch to real backend:
} from './salesService';
```

Both files export identical function signatures. See `BACKEND_CONTRACT.md` for what the backend must implement.

---

## Project layout

```
src/
  types/            # Shared TypeScript interfaces
    index.ts        # Core types (QueryParams, FieldConfig, Preset, etc.)
    sales.ts        # Sales page-specific types
  hooks/
    useDashboardState.ts  # Core shared state hook — powers every page
  services/
    dataService.ts        # Fetch helpers (used by real service files)
    urlSerializer.ts      # URL ↔ QueryParams serialization
  components/
    AppShell/             # Layout shell (header, command zone, sidebar slot, main)
    ControlSidebar/       # Shared sidebar chrome + page-specific children slot
    PresetBar/            # Preset chip strip (part of command zone)
    AppliedParamsBar/     # Applied params display (part of command zone)
    FieldPicker/          # Measure radio + Group By drag-and-drop
    Dashboard/            # Card grid + data fetching orchestration
    charts/               # Highcharts wrappers
    grids/                # AG Grid wrappers
    shared/               # KVDropdown, PresetSaveModal
  pages/
    SalesView/            # Sales dashboard — the first production page
      index.tsx           # Page composition + wiring
      mockService.ts      # Mock implementation (active by default)
      salesService.ts     # Real backend implementation (swap in when ready)
  styles/
    _variables.scss       # All design tokens and CSS custom properties
```

---

## Environment

No environment variables are required to run with mock data.

When connecting the real backend, set the base URL in `src/services/dataService.ts`:

```ts
const BASE_URL = 'http://localhost:8080';  // point at your KDB+ HTTP server
```
