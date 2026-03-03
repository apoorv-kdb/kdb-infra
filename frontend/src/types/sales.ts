import { KVOption, FieldConfig, BaseImmediateState, WithComparison, WithTrend, Preset, CatalogField } from './index';

// =============================================
// SALES IMMEDIATE STATE
// Opts into both comparison and trend features
// =============================================
export interface SalesImmediateState extends BaseImmediateState, WithComparison, WithTrend {}

// =============================================
// SALES DRAFT STATE (deferred — Apply button gates this)
// =============================================
export interface SalesDraftState {
  filters:      KVOption[];
  exclusions:   KVOption[];
  fieldConfigs: FieldConfig[];
  measure:      string | null;
}

// =============================================
// PRESET — deferred only, dates never stored
// =============================================
export type SalesPresetState = SalesDraftState;
export type SalesPreset      = Preset<SalesPresetState>;

// =============================================
// INIT RESPONSE — GET /api/sales/init
// =============================================
export interface SalesInitResponse {
  latestAsofDate:  string;
  defaultPrevDate: string;
  catalogFields:   CatalogField[];
  filterOptions:   KVOption[];
  presets:         SalesPreset[];
}

// =============================================
// DEFAULTS
// =============================================
export const DEFAULT_SALES_IMMEDIATE: SalesImmediateState = {
  asofDate:    null,
  prevDate:    null,
  mode:        'movement',
  chartWindow: '30d',
};

export const DEFAULT_SALES_DRAFT: SalesDraftState = {
  filters:      [],
  exclusions:   [],
  fieldConfigs: [],
  measure:      null,
};
