export interface KVOption { key: string; value: string; }

// =============================================
// CATALOG TYPES
// =============================================
export interface CatalogField {
  field:     string;
  label:     string;
  fieldType: 'categorical' | 'value';
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

export interface SpotRow {
  [field: string]: string | number;
  value: number;
  pct:   number;
}

// =============================================
// FIELD CONFIG
// =============================================
export interface FieldConfig {
  field:     string;
  showTable: boolean;
  showChart: boolean;
}

// =============================================
// ANALYTICAL MODE
// =============================================
export type AnalyticalMode = 'movement' | 'spot';

// =============================================
// GENERIC PRESET
// TState is page-specific — never includes dates
// =============================================
export interface Preset<TState = unknown> {
  id:        string;
  name:      string;
  group:     string;
  isDefault: boolean;
  order:     number;
  state:     TState;
}

// =============================================
// BASE IMMEDIATE STATE
// =============================================
export interface BaseImmediateState {
  asofDate: string | null;
}

// Optional feature bundles
export interface WithComparison {
  prevDate: string | null;
  mode:     AnalyticalMode;
}

export interface WithTrend {
  chartWindow: '30d' | '60d' | '90d' | '1Y';
}

// =============================================
// QUERY PARAMS — sent to backend / dashboard
// =============================================
export interface QueryParams {
  asofDate:     string | null;
  prevDate?:    string | null;
  filters:      Record<string, string[]>;
  exclusions:   Record<string, string[]>;
  chartWindow?: '30d' | '60d' | '90d' | '1Y';
  measure:      string | null;
  mode?:        AnalyticalMode;
  fieldConfigs: FieldConfig[];
}

// =============================================
// DATA TYPES
// =============================================
export interface TrendByDimensionPoint {
  date:     string;
  category: string;
  value:    number;
}
