/**
 * mockData.ts
 * Static mock data matching KDB+ query contract shapes exactly.
 */

import { CatalogField, KVOption, FlatRow, SpotRow, TrendByDimensionPoint } from '../types';

// ─── Catalog ──────────────────────────────────────────────────────────────────
export const MOCK_CATALOG_FIELDS: CatalogField[] = [
  { field: 'region',         label: 'Region',         fieldType: 'categorical' },
  { field: 'product',        label: 'Product',        fieldType: 'categorical' },
  { field: 'total_quantity', label: 'Total Quantity', fieldType: 'value' },
  { field: 'total_revenue',  label: 'Total Revenue',  fieldType: 'value' },
];

// ─── Filter Options ───────────────────────────────────────────────────────────
export const MOCK_FILTER_OPTIONS: KVOption[] = [
  { key: 'region', value: 'AMER' },
  { key: 'region', value: 'APAC' },
  { key: 'region', value: 'EMEA' },
  { key: 'product', value: 'WidgetA' },
  { key: 'product', value: 'WidgetB' },
  { key: 'product', value: 'WidgetC' },
];

// ─── Movement data ────────────────────────────────────────────────────────────
export const MOCK_MOVEMENT_BY_FIELD: Record<string, FlatRow[]> = {
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

// ─── Spot data ────────────────────────────────────────────────────────────────
export const MOCK_SPOT_BY_FIELD: Record<string, SpotRow[]> = {
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
  for (let i = 0; i < seed.length; i++) {
    h = Math.imul(31, h) + seed.charCodeAt(i) | 0;
  }
  const f = ((h >>> 0) / 0xffffffff) * 2 - 1;
  return f * magnitude;
};

export const buildMockTrend = (
  field: string,
  endDateStr: string,
  startDateStr: string,
): TrendByDimensionPoint[] => {
  const categories = TREND_CATEGORIES[field] ?? ['Unknown'];
  const baseValues  = BASE_VALUES[field] ?? {};
  const end   = new Date(endDateStr);
  const start = new Date(startDateStr);
  const rows: TrendByDimensionPoint[] = [];

  for (let d = new Date(start); d <= end; d.setDate(d.getDate() + 1)) {
    const dow = d.getDay();
    if (dow === 0 || dow === 6) continue;
    const dateStr = d.toISOString().split('T')[0];
    for (const cat of categories) {
      const base   = baseValues[cat] ?? 10000;
      const seed   = `${field}-${cat}-${dateStr}`;
      const jitter = seededJitter(seed, base * 0.08);
      const trend  = (d.getTime() - start.getTime()) / (1000 * 60 * 60 * 24) * (base * 0.001);
      const value  = Math.max(0, Math.round((base + jitter + trend) * 100) / 100);
      rows.push({ date: dateStr, category: cat, value });
    }
  }
  return rows;
};

export const windowToStartDate = (asofDate: string, window: string): string => {
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
