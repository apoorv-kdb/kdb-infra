export interface KVOption { key: string; value: string; }

// =============================================
// CATALOG TYPES
// =============================================
export interface CatalogField {
  field: string;
  label: string;
  type:  'categorical' | 'value';
}

export interface DimensionDef {
  field:      string;
  headerName: string;
  width?:     number;
}

export interface MeasureDef {
  field:      string;
  headerName: string;
  aggFunc:    'sum' | 'avg' | 'last';
  formatter:  'currency' | 'number' | 'percent';
  width?:     number;
}

export interface TableColumnConfig {
  dimensions: DimensionDef[];
  measures:   MeasureDef[];
}

export type FlatRow = Record<string, string | number | null>;

// =============================================
// FIELD CONFIG
// One entry per catalog dimension.
// Ordered — order controls dashboard panel order.
// showTable → renders DoD comparison table grouped by this field
// showChart → renders multi-line trend chart split by this field
// =============================================
export interface FieldConfig {
  field:     string;
  showTable: boolean;
  showChart: boolean;
}

// =============================================
// CONTROL BAR STATE
// =============================================
export interface ControlBarState {
  asofDate:     string | null;
  prevDate:     string | null;
  filters:      KVOption[];
  exclusions:   KVOption[];
  chartWindow:  '30d' | '60d' | '90d' | '1Y';
  measure:      string | null;
  fieldConfigs: FieldConfig[];   // replaces selectedTables + selectedCharts + groupBy
}

export const DEFAULT_CONTROL_BAR_STATE: ControlBarState = {
  asofDate: null, prevDate: null,
  filters: [], exclusions: [],
  chartWindow: '30d',
  measure: null,
  fieldConfigs: [],
};

// =============================================
// QUERY PARAMS
// =============================================
export interface QueryParams {
  asofDate:     string | null;
  prevDate:     string | null;
  filters:      Record<string, string[]>;
  exclusions:   Record<string, string[]>;
  chartWindow:  '30d' | '60d' | '90d' | '1Y';
  measure:      string | null;
  fieldConfigs: FieldConfig[];
}

export const toQueryParams = (state: ControlBarState): QueryParams => {
  const collapse = (pairs: KVOption[]): Record<string, string[]> =>
    pairs.reduce((acc, { key, value }) => {
      acc[key] = [...(acc[key] ?? []), value];
      return acc;
    }, {} as Record<string, string[]>);
  return {
    asofDate:     state.asofDate,
    prevDate:     state.prevDate,
    filters:      collapse(state.filters),
    exclusions:   collapse(state.exclusions),
    chartWindow:  state.chartWindow,
    measure:      state.measure,
    fieldConfigs: state.fieldConfigs,
  };
};

// =============================================
// PRESETS
// =============================================
export interface Preset {
  id:        string;
  name:      string;
  group:     string;
  isDefault: boolean;
  state:     ControlBarState;
  createdAt: string;
}

// =============================================
// DATA TYPES
// =============================================
export interface Transaction   { date: string; region: string; product: string; quantity: number; revenue: number; }
export interface RegionSummary { region: string; asofRevenue: number; prevRevenue: number; change: number; changePct: number; }
export interface TrendPoint    { date: string; revenue: number; }

// Multi-line trend: one row per date × category
export interface TrendByDimensionPoint {
  date:     string;
  category: string;  // e.g. 'EMEA', 'WidgetA'
  value:    number;
}
