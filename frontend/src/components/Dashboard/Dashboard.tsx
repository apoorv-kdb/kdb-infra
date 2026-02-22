import { useState, useEffect, useRef } from 'react';
import {
  QueryParams, FlatRow, Transaction,
  TableColumnConfig, TrendByDimensionPoint, CatalogField,
} from '../../types';
import RegionSummaryGrid from '../grids/RegionSummaryGrid/RegionSummaryGrid';
import MultiLineTrendChart from '../charts/MultiLineTrendChart/MultiLineTrendChart';
import './Dashboard.scss';

interface DashboardProps {
  params:               QueryParams;
  catalogFields:        CatalogField[];
  getRegionSummaryFlat: (p: QueryParams, field: string) => Promise<FlatRow[]>;
  getTransactions:      (p: QueryParams) => Promise<Transaction[]>;
  getTrendByDimension:  (p: QueryParams, field: string) => Promise<TrendByDimensionPoint[]>;
}

type CardType = 'table' | 'chart';

const DashboardCard = ({ title, type, children }: {
  title: string; type: CardType; children: React.ReactNode;
}) => (
  <div className={`dashboard-card dashboard-card--${type}`}>
    <div className={`dashboard-card__header dashboard-card__header--${type}`}>
      <span className="dashboard-card__title">{title}</span>
    </div>
    <div className="dashboard-card__body">{children}</div>
  </div>
);

const buildColumnConfig = (field: string, fieldLabel: string, measure: string): TableColumnConfig => {
  const MEASURE_LABELS: Record<string, string> = {
    revenue: 'Revenue', quantity: 'Quantity', price: 'Price',
  };
  const mLabel = MEASURE_LABELS[measure] ?? measure;
  return {
    dimensions: [{ field, headerName: fieldLabel, width: 130 }],
    measures: [
      { field: 'asofValue', headerName: `${mLabel} (AsOf)`, aggFunc: 'sum', formatter: 'currency' },
      { field: 'prevValue', headerName: `${mLabel} (Prev)`, aggFunc: 'sum', formatter: 'currency' },
      { field: 'change',    headerName: 'Change',            aggFunc: 'sum', formatter: 'currency' },
      { field: 'changePct', headerName: 'Chg %',             aggFunc: 'avg', formatter: 'percent', width: 85 },
    ],
  };
};

// Data for a single panel — undefined means not yet fetched
interface PanelData {
  tableData:    FlatRow[]                | null;  // null = not requested
  chartData:    TrendByDimensionPoint[]  | null;  // null = not requested
  tableLoading: boolean;
  chartLoading: boolean;
  error?:       string;
}

const Dashboard = ({
  params, catalogFields, getRegionSummaryFlat, getTransactions, getTrendByDimension,
}: DashboardProps) => {
  const { fieldConfigs, measure, chartWindow } = params;
  const activeConfigs = fieldConfigs.filter(c => c.showTable || c.showChart);

  // Keyed by field name
  const [panelData, setPanelData] = useState<Record<string, PanelData>>({});

  // Track current fetch generation — if params change mid-flight, discard stale results
  const fetchGen = useRef(0);

  useEffect(() => {
    if (activeConfigs.length === 0) return;

    // Increment generation — any in-flight fetches from previous params will be discarded
    const gen = ++fetchGen.current;

    // Initialise all panels as loading immediately (no flicker to undefined)
    const initialState: Record<string, PanelData> = {};
    for (const config of activeConfigs) {
      initialState[config.field] = {
        tableData:    config.showTable ? [] : null,
        chartData:    config.showChart ? [] : null,
        tableLoading: config.showTable,
        chartLoading: config.showChart,
      };
    }
    setPanelData(initialState);

    // Fire fetches per field — each updates only its own slice
    for (const config of activeConfigs) {
      const { field } = config;

      if (config.showTable) {
        getRegionSummaryFlat(params, field)
          .then(data => {
            if (fetchGen.current !== gen) return; // stale, discard
            setPanelData(prev => ({
              ...prev,
              [field]: { ...prev[field], tableData: data, tableLoading: false },
            }));
          })
          .catch(err => {
            if (fetchGen.current !== gen) return;
            console.error(`Table fetch failed for ${field}:`, err);
            setPanelData(prev => ({
              ...prev,
              [field]: { ...prev[field], tableLoading: false, error: String(err) },
            }));
          });
      }

      if (config.showChart) {
        getTrendByDimension(params, field)
          .then(data => {
            if (fetchGen.current !== gen) return;
            setPanelData(prev => ({
              ...prev,
              [field]: { ...prev[field], chartData: data, chartLoading: false },
            }));
          })
          .catch(err => {
            if (fetchGen.current !== gen) return;
            console.error(`Chart fetch failed for ${field}:`, err);
            setPanelData(prev => ({
              ...prev,
              [field]: { ...prev[field], chartLoading: false, error: String(err) },
            }));
          });
      }
    }
  }, [params]); // eslint-disable-line react-hooks/exhaustive-deps

  const getFieldLabel = (field: string) =>
    catalogFields.find(f => f.field === field)?.label ?? field;

  if (activeConfigs.length === 0) {
    return (
      <div className="dashboard__empty">
        Select fields in the sidebar and click Apply.
      </div>
    );
  }

  return (
    <div className="dashboard__flow">
      {activeConfigs.map(config => {
        const { field }    = config;
        const state        = panelData[field];
        const fieldLabel   = getFieldLabel(field);
        const m            = measure ?? 'revenue';
        const colConfig    = buildColumnConfig(field, fieldLabel, m);

        // Before effect has fired (very first render), treat as loading
        const tableLoading = state?.tableLoading ?? config.showTable;
        const chartLoading = state?.chartLoading ?? config.showChart;

        return (
          <>
            {config.showTable && (
              <DashboardCard
                key={`${field}-table`}
                title={`${fieldLabel} — DoD Comparison`}
                type="table"
              >
                <RegionSummaryGrid
                  data={state?.tableData ?? []}
                  loading={tableLoading}
                  config={colConfig}
                />
              </DashboardCard>
            )}

            {config.showChart && (
              <DashboardCard
                key={`${field}-chart`}
                title={`${fieldLabel} — Trend`}
                type="chart"
              >
                <MultiLineTrendChart
                  data={state?.chartData ?? []}
                  field={field}
                  fieldLabel={fieldLabel}
                  measure={m}
                  window={chartWindow}
                  loading={chartLoading}
                />
              </DashboardCard>
            )}
          </>
        );
      })}
    </div>
  );
};

export default Dashboard;
