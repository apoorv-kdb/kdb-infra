/**
 * salesService.ts
 * Real KDB+ backend — identical signatures to mockService.ts
 * TO USE: swap import in SalesView/index.tsx
 */

import { QueryParams, FlatRow, SpotRow, TrendByDimensionPoint } from '../../types';
import { SalesPreset, SalesPresetState } from '../../types/sales';
import { kdbGet, kdbPost } from '../../services/dataService';
import { InitData } from '../../hooks/useDashboardState';

// ─── Init ─────────────────────────────────────────────────────────────────────
export const getInitData = (): Promise<InitData<SalesPresetState>> =>
  kdbGet<InitData<SalesPresetState>>('/api/sales/init');

// ─── Helpers ──────────────────────────────────────────────────────────────────
const windowToStartDate = (asofDate: string, window: string): string => {
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

// ─── Movement ─────────────────────────────────────────────────────────────────
export const getRegionSummaryFlat = (params: QueryParams, field: string): Promise<FlatRow[]> => {
  if (!params.asofDate || !params.prevDate) return Promise.resolve([]);
  return kdbPost<FlatRow[]>('/api/sales/query/table', {
    field,
    measure:    params.measure ?? 'total_revenue',
    asofDate:   params.asofDate,
    prevDate:   params.prevDate,
    filters:    params.filters,
    exclusions: params.exclusions,
  });
};

// ─── Spot ─────────────────────────────────────────────────────────────────────
export const getSpotData = (params: QueryParams, field: string, topN?: number): Promise<SpotRow[]> => {
  if (!params.asofDate) return Promise.resolve([]);
  return kdbPost<SpotRow[]>('/api/sales/query/spot', {
    field,
    measure:    params.measure ?? 'total_revenue',
    asofDate:   params.asofDate,
    topN:       topN ?? 0,
    filters:    params.filters,
    exclusions: params.exclusions,
  });
};

// ─── Trend ────────────────────────────────────────────────────────────────────
export const getTrendByDimension = (params: QueryParams, field: string): Promise<FlatRow[]> => {
  if (!params.asofDate) return Promise.resolve([]);
  return kdbPost<FlatRow[]>('/api/sales/query/trend', {
    categoryField: field,
    measure:       params.measure ?? 'total_revenue',
    startDate:     windowToStartDate(params.asofDate, params.chartWindow ?? '30d'),
    endDate:       params.asofDate,
    filters:       params.filters,
    exclusions:    params.exclusions,
  });
};

// ─── Preset CRUD ──────────────────────────────────────────────────────────────
export const savePreset = (state: SalesPresetState, name: string, group: string): Promise<SalesPreset> =>
  kdbPost<SalesPreset>('/api/sales/presets', { state, name, group });

export const deletePreset = (id: string): Promise<void> =>
  kdbPost<void>(`/api/sales/presets/${id}/delete`, {});

export const setDefaultPreset = (id: string): Promise<void> =>
  kdbPost<void>(`/api/sales/presets/${id}/default`, {});
