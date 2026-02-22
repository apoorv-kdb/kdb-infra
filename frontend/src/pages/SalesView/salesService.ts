// salesService.ts
// All data fetching for the Sales dashboard — wired to real KDB+ endpoints
// Mock data has been removed; all functions hit the server at localhost:5010

import { QueryParams, FlatRow, KVOption, CatalogField, TrendByDimensionPoint } from '../../types';
import { kdbGet, kdbPost } from '../../services/dataService';

export const WINDOW_OPTIONS = [
  { label: '30 Days', value: '30d' },
  { label: '60 Days', value: '60d' },
  { label: '90 Days', value: '90d' },
  { label: '1 Year',  value: '1Y'  },
];

// =============================================
// CATALOG
// Fetched from KDB+ on app load — replaces hardcoded CATALOG_FIELDS
// =============================================

// GET /catalog/fields → [{field, label, type, format}]
// KDB+ returns role as 'type' to match the CatalogField interface directly
export const getCatalogFields = (): Promise<CatalogField[]> =>
  kdbGet<CatalogField[]>('/catalog/fields');

// GET /catalog/filter-options → [{key, value}]
// Returns ALL categorical field values in one call — key = field name, value = field value
export const getFilterOptions = (): Promise<KVOption[]> =>
  kdbGet<KVOption[]>('/catalog/filter-options');

// =============================================
// HELPERS
// =============================================

// Convert chartWindow ('30d'|'60d'|'90d'|'1Y') + asofDate to ISO startDate string
const windowToStartDate = (asofDate: string, window: string): string => {
  const d = new Date(asofDate);
  switch (window) {
    case '30d': d.setDate(d.getDate() - 30);  break;
    case '60d': d.setDate(d.getDate() - 60);  break;
    case '90d': d.setDate(d.getDate() - 90);  break;
    case '1Y':  d.setFullYear(d.getFullYear() - 1); break;
    default:    d.setDate(d.getDate() - 30);
  }
  return d.toISOString().split('T')[0]; // "2024-01-13"
};

// Collapse filters/exclusions KVOption[] to Record<string, string[]>
// for sending to KDB+: [{key:'region',value:'AMER'},...] → {region:['AMER',...]}
const collapseFilters = (pairs: KVOption[]): Record<string, string[]> =>
  pairs.reduce((acc, { key, value }) => {
    acc[key] = [...(acc[key] ?? []), value];
    return acc;
  }, {} as Record<string, string[]>);

// =============================================
// POST /query/table
// DoD comparison — one row per unique value of `field`
// Returns [{<field>: <value>, asofValue, prevValue, change, changePct}]
// =============================================
export const getRegionSummaryFlat = async (
  params: QueryParams,
  field: string,
): Promise<FlatRow[]> => {
  if (!params.asofDate || !params.prevDate) {
    return [];
  }
  return kdbPost<FlatRow[]>('/query/table', {
    field,
    measure:     params.measure ?? 'total_revenue',
    asofDate:    params.asofDate,
    prevDate:    params.prevDate,
    filters:     collapseFilters(params.filters as unknown as KVOption[]),
    exclusions:  collapseFilters(params.exclusions as unknown as KVOption[]),
  });
};

// =============================================
// POST /query/trend
// Date × category time series
// Returns [{date, category, value}]
// =============================================
export const getTrendByDimension = async (
  params: QueryParams,
  field: string,
): Promise<TrendByDimensionPoint[]> => {
  if (!params.asofDate) return [];

  const endDate   = params.asofDate;
  const startDate = windowToStartDate(params.asofDate, params.chartWindow);

  return kdbPost<TrendByDimensionPoint[]>('/query/trend', {
    categoryField: field,
    measure:       params.measure ?? 'total_revenue',
    startDate,
    endDate,
    filters:       collapseFilters(params.filters as unknown as KVOption[]),
    exclusions:    collapseFilters(params.exclusions as unknown as KVOption[]),
  });
};
