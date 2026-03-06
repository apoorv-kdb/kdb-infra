/**
 * mockService.ts
 * Drop-in replacement for salesService.ts — identical function signatures.
 * TO CONNECT REAL BACKEND: change one import line in SalesView/index.tsx.
 *
 * All mock data lives here — no separate mockData.ts needed.
 */

import { QueryParams, CatalogField, KVOption, FlatRow, SpotRow, TrendByDimensionPoint } from '../../types';
import { SalesPreset, SalesPresetState } from '../../types/sales';
import { InitData } from '../../hooks/useDashboardState';

const delay = (ms = 350) => new Promise<void>(res => setTimeout(res, ms));

// ─── Static catalog data ──────────────────────────────────────────────────────
const CATALOG_FIELDS: CatalogField[] = [
  { field: 'region',         label: 'Region',         fieldType: 'categorical' },
  { field: 'product',        label: 'Product',        fieldType: 'categorical' },
  { field: 'total_quantity', label: 'Total Quantity', fieldType: 'value' },
  { field: 'total_revenue',  label: 'Total Revenue',  fieldType: 'value' },
];

const FILTER_OPTIONS: KVOption[] = [
  { key: 'region',  value: 'AMER'    },
  { key: 'region',  value: 'APAC'    },
  { key: 'region',  value: 'EMEA'    },
  { key: 'product', value: 'WidgetA' },
  { key: 'product', value: 'WidgetB' },
  { key: 'product', value: 'WidgetC' },
];

// ─── Static movement + spot data ─────────────────────────────────────────────
const MOVEMENT_BY_FIELD: Record<string, FlatRow[]> = {
  region: [
    { region: 'AMER', asofValue: 21134.34, prevValue: 19676.95, change:  1457.39, changePct:  0.0741 },
    { region: 'APAC', asofValue:  9623.16, prevValue:  8504.35, change:  1118.81, changePct:  0.1316 },
    { region: 'EMEA', asofValue: 14431.35, prevValue: 14130.27, change:   301.08, changePct:  0.0213 },
  ],
  product: [
    { product: 'WidgetA', asofValue: 18342.20, prevValue: 17100.00, change:  1242.20, changePct:  0.0727 },
    { product: 'WidgetB', asofValue: 14823.50, prevValue: 15200.00, change:  -376.50, changePct: -0.0248 },
    { product: 'WidgetC', asofValue: 12023.15, prevValue: 10011.57, change:  2011.58, changePct:  0.2009 },
  ],
};

const SPOT_BY_FIELD: Record<string, SpotRow[]> = {
  region: [
    { region: 'AMER', value: 21134.34, pct: 0.4730 },
    { region: 'EMEA', value: 14431.35, pct: 0.3229 },
    { region: 'APAC', value:  9623.16, pct: 0.2154 },
  ],
  product: [
    { product: 'WidgetA', value: 18342.20, pct: 0.4104 },
    { product: 'WidgetB', value: 14823.50, pct: 0.3317 },
    { product: 'WidgetC', value: 12023.15, pct: 0.2691 },
  ],
};

// ─── Trend data generator ─────────────────────────────────────────────────────
const TREND_CATEGORIES: Record<string, string[]> = {
  region:  ['AMER', 'APAC', 'EMEA'],
  product: ['WidgetA', 'WidgetB', 'WidgetC'],
};

const BASE_VALUES: Record<string, Record<string, number>> = {
  region:  { AMER: 20000, APAC: 9000, EMEA: 14000 },
  product: { WidgetA: 17500, WidgetB: 15000, WidgetC: 11500 },
};

const seededJitter = (seed: string, magnitude: number): number => {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = Math.imul(31, h) + seed.charCodeAt(i) | 0;
  return (((h >>> 0) / 0xffffffff) * 2 - 1) * magnitude;
};

const buildTrend = (field: string, startDateStr: string, endDateStr: string): TrendByDimensionPoint[] => {
  const categories = TREND_CATEGORIES[field] ?? ['Unknown'];
  const baseValues  = BASE_VALUES[field] ?? {};
  const start = new Date(startDateStr);
  const end   = new Date(endDateStr);
  const rows: TrendByDimensionPoint[] = [];
  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
    const dow = d.getDay();
    if (dow === 0 || dow === 6) continue;
    const dateStr = d.toISOString().split('T')[0];
    for (const cat of categories) {
      const base   = baseValues[cat] ?? 10000;
      const jitter = seededJitter(`${field}-${cat}-${dateStr}`, base * 0.08);
      const trend  = (d.getTime() - start.getTime()) / 86400000 * (base * 0.001);
      rows.push({ date: dateStr, category: cat, value: Math.max(0, Math.round((base + jitter + trend) * 100) / 100) });
    }
  }
  return rows;
};

const windowToStart = (asofDate: string, window: string): string => {
  const d = new Date(asofDate);
  switch (window) {
    case '30d': d.setDate(d.getDate() - 30);        break;
    case '60d': d.setDate(d.getDate() - 60);        break;
    case '90d': d.setDate(d.getDate() - 90);        break;
    case '1Y':  d.setFullYear(d.getFullYear() - 1); break;
    default:    d.setDate(d.getDate() - 30);
  }
  return d.toISOString().split('T')[0];
};

// ─── Filter helper ────────────────────────────────────────────────────────────
const applyFilters = <T extends Record<string, unknown>>(
  rows: T[],
  filters: Record<string, string[]>,
  exclusions: Record<string, string[]>,
): T[] =>
  rows.filter(row => {
    for (const [key, values] of Object.entries(filters))
      if (values.length && key in row && !values.includes(String(row[key] ?? ''))) return false;
    for (const [key, values] of Object.entries(exclusions))
      if (values.length && key in row && values.includes(String(row[key] ?? ''))) return false;
    return true;
  });

// ─── Presets ──────────────────────────────────────────────────────────────────
const INITIAL_PRESETS: SalesPreset[] = [
  {
    id: 'preset-1', name: 'Default View', group: 'My Presets', isDefault: true, order: 0,
    state: { filters: [], exclusions: [], measure: 'total_quantity', fieldConfigs: [
      { field: 'region',  showTable: true, showChart: true },
      { field: 'product', showTable: true, showChart: true },
    ]},
  },
  {
    id: 'preset-2', name: 'Region Only', group: 'My Presets', isDefault: false, order: 1,
    state: { filters: [], exclusions: [], measure: 'total_revenue', fieldConfigs: [
      { field: 'region', showTable: true, showChart: true },
    ]},
  },
  {
    id: 'preset-3', name: 'AMER Focus', group: 'Shared', isDefault: false, order: 2,
    state: { filters: [{ key: 'region', value: 'AMER' }], exclusions: [], measure: 'total_revenue', fieldConfigs: [
      { field: 'region',  showTable: true,  showChart: false },
      { field: 'product', showTable: true,  showChart: true  },
    ]},
  },
  // Overflow test presets — verifies PresetBar More menu scroll behaviour
  ...['A','B','C','D','E','F','G','H','I','J','K','L','M','N','O'].map((l, i) => ({
    id: `preset-${i + 4}`, name: `Shared View ${l}`, group: 'Shared' as const,
    isDefault: false, order: i + 3,
    state: { filters: [] as SalesPreset['state']['filters'], exclusions: [] as SalesPreset['state']['exclusions'],
             measure: 'total_revenue' as const, fieldConfigs: [{ field: 'region', showTable: true, showChart: true }] },
  })),
];

let _presets = [...INITIAL_PRESETS];

// ─── Exported service functions ───────────────────────────────────────────────
export const getInitData = async (): Promise<InitData<SalesPresetState>> => {
  await delay(200);
  return {
    latestAsofDate:  '2026-02-26',
    defaultPrevDate: '2026-01-27',
    catalogFields:   CATALOG_FIELDS,
    filterOptions:   FILTER_OPTIONS,
    presets:         _presets,
  };
};

export const getRegionSummaryFlat = async (params: QueryParams, field: string): Promise<FlatRow[]> => {
  if (!params.asofDate || !params.prevDate) return [];
  await delay(300);
  const rows = MOVEMENT_BY_FIELD[field] ?? [];
  return applyFilters(rows as Record<string, unknown>[], params.filters, params.exclusions) as FlatRow[];
};

export const getSpotData = async (params: QueryParams, field: string, topN?: number): Promise<SpotRow[]> => {
  if (!params.asofDate) return [];
  await delay(280);
  let rows = applyFilters(
    (SPOT_BY_FIELD[field] ?? []) as Record<string, unknown>[],
    params.filters, params.exclusions,
  ) as SpotRow[];
  const total = rows.reduce((s, r) => s + r.value, 0);
  rows = rows.map(r => ({ ...r, pct: total > 0 ? r.value / total : 0 }));
  if (topN && topN > 0) rows = rows.slice(0, topN);
  return rows;
};

export const getTrendByDimension = async (params: QueryParams, field: string): Promise<TrendByDimensionPoint[]> => {
  if (!params.asofDate) return [];
  await delay(420);
  const startDate = windowToStart(params.asofDate, params.chartWindow ?? '30d');
  let rows = buildTrend(field, startDate, params.asofDate);
  const inc = (params.filters)[field]    ?? [];
  const exc = (params.exclusions)[field] ?? [];
  if (inc.length) rows = rows.filter(r =>  inc.includes(r.category));
  if (exc.length) rows = rows.filter(r => !exc.includes(r.category));
  return rows;
};

export const savePreset = async (state: SalesPresetState, name: string, group: string): Promise<SalesPreset> => {
  await delay(150);
  const preset: SalesPreset = {
    id: crypto.randomUUID(), name: name.trim(),
    group: group.trim() || 'My Presets', isDefault: false, order: _presets.length, state,
  };
  _presets = [..._presets, preset];
  return preset;
};

export const deletePreset  = async (id: string): Promise<void> => { await delay(100); _presets = _presets.filter(p => p.id !== id); };
export const setDefaultPreset = async (id: string): Promise<void> => { await delay(100); _presets = _presets.map(p => ({ ...p, isDefault: p.id === id })); };
