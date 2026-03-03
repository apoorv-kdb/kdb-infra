/**
 * mockService.ts
 * Drop-in replacement for salesService.ts — identical function signatures.
 * TO CONNECT REAL BACKEND: change one import line in SalesView/index.tsx.
 */

import { QueryParams, FlatRow, SpotRow, TrendByDimensionPoint, KVOption } from '../../types';
import { SalesInitResponse, SalesPreset, SalesPresetState } from '../../types/sales';
import {
  MOCK_CATALOG_FIELDS, MOCK_FILTER_OPTIONS,
  MOCK_MOVEMENT_BY_FIELD, MOCK_SPOT_BY_FIELD,
  buildMockTrend, windowToStartDate,
} from '../../services/mockData';
import { InitData } from '../../hooks/useDashboardState';

const delay = (ms = 350) => new Promise<void>(res => setTimeout(res, ms));

// ─── Mock presets ─────────────────────────────────────────────────────────────
const MOCK_PRESETS: SalesPreset[] = [
  {
    id: 'preset-1',
    name: 'Default View',
    group: 'My Presets',
    isDefault: true,
    order: 0,
    state: {
      filters:      [],
      exclusions:   [],
      measure:      'total_quantity',
      fieldConfigs: [
        { field: 'region',  showTable: true, showChart: true },
        { field: 'product', showTable: true, showChart: true },
      ],
    },
  },
  {
    id: 'preset-2',
    name: 'Region Only',
    group: 'My Presets',
    isDefault: false,
    order: 1,
    state: {
      filters:      [],
      exclusions:   [],
      measure:      'total_revenue',
      fieldConfigs: [{ field: 'region', showTable: true, showChart: true }],
    },
  },
  {
    id: 'preset-3',
    name: 'AMER Focus',
    group: 'Shared',
    isDefault: false,
    order: 2,
    state: {
      filters:      [{ key: 'region', value: 'AMER' }],
      exclusions:   [],
      measure:      'total_revenue',
      fieldConfigs: [
        { field: 'region',  showTable: true,  showChart: false },
        { field: 'product', showTable: true,  showChart: true  },
      ],
    },
  },
];

// ─── Init ─────────────────────────────────────────────────────────────────────
export const getInitData = async (): Promise<InitData<SalesPresetState>> => {
  await delay(200);
  return {
    latestAsofDate:  '2026-02-26',
    defaultPrevDate: '2026-01-27',
    catalogFields:   MOCK_CATALOG_FIELDS,
    filterOptions:   MOCK_FILTER_OPTIONS,
    presets:         MOCK_PRESETS,
  };
};

// ─── Query helpers ────────────────────────────────────────────────────────────
const applyFilters = <T extends Record<string, unknown>>(
  rows: T[],
  filters: Record<string, string[]>,
  exclusions: Record<string, string[]>,
): T[] =>
  rows.filter(row => {
    for (const [key, values] of Object.entries(filters)) {
      // Only filter on keys the row actually has — a product row doesn't have region
      if (values.length && key in row && !values.includes(String(row[key] ?? ''))) return false;
    }
    for (const [key, values] of Object.entries(exclusions)) {
      if (values.length && key in row && values.includes(String(row[key] ?? ''))) return false;
    }
    return true;
  });

// ─── Movement ─────────────────────────────────────────────────────────────────
export const getRegionSummaryFlat = async (params: QueryParams, field: string): Promise<FlatRow[]> => {
  if (!params.asofDate || !params.prevDate) return [];
  await delay(300);
  const rows = MOCK_MOVEMENT_BY_FIELD[field] ?? [];
  return applyFilters(rows as Record<string, unknown>[], params.filters, params.exclusions) as FlatRow[];
};

// ─── Spot ─────────────────────────────────────────────────────────────────────
export const getSpotData = async (params: QueryParams, field: string, topN?: number): Promise<SpotRow[]> => {
  if (!params.asofDate) return [];
  await delay(280);
  let rows = MOCK_SPOT_BY_FIELD[field] ?? [];
  rows = applyFilters(rows as Record<string, unknown>[], params.filters, params.exclusions) as SpotRow[];
  const total = rows.reduce((s, r) => s + r.value, 0);
  rows = rows.map(r => ({ ...r, pct: total > 0 ? r.value / total : 0 }));
  if (topN && topN > 0) rows = rows.slice(0, topN);
  return rows;
};

// ─── Trend ────────────────────────────────────────────────────────────────────
export const getTrendByDimension = async (params: QueryParams, field: string): Promise<TrendByDimensionPoint[]> => {
  if (!params.asofDate) return [];
  await delay(420);
  const endDate   = params.asofDate;
  const startDate = windowToStartDate(params.asofDate, params.chartWindow ?? '30d');
  let rows = buildMockTrend(field, endDate, startDate);
  const fieldFilters  = (params.filters)[field]   ?? [];
  const fieldExcludes = (params.exclusions)[field] ?? [];
  if (fieldFilters.length)  rows = rows.filter(r => fieldFilters.includes(r.category));
  if (fieldExcludes.length) rows = rows.filter(r => !fieldExcludes.includes(r.category));
  return rows;
};

// ─── Preset CRUD ──────────────────────────────────────────────────────────────
let _presets = [...MOCK_PRESETS];

export const savePreset = async (state: SalesPresetState, name: string, group: string): Promise<SalesPreset> => {
  await delay(150);
  const preset: SalesPreset = {
    id: crypto.randomUUID(),
    name: name.trim(),
    group: group.trim() || 'My Presets',
    isDefault: false,
    order: _presets.length,
    state,
  };
  _presets = [..._presets, preset];
  return preset;
};

export const deletePreset = async (id: string): Promise<void> => {
  await delay(100);
  _presets = _presets.filter(p => p.id !== id);
};

export const setDefaultPreset = async (id: string): Promise<void> => {
  await delay(100);
  _presets = _presets.map(p => ({ ...p, isDefault: p.id === id }));
};

// Keep for backwards compat with anything that still imports it
export const WINDOW_OPTIONS = [
  { label: '30 Days', value: '30d' },
  { label: '60 Days', value: '60d' },
  { label: '90 Days', value: '90d' },
  { label: '1 Year',  value: '1Y'  },
];
