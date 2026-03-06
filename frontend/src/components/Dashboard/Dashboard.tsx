import { useState, useEffect, useRef, Fragment } from 'react';
import {
  QueryParams, FlatRow, SpotRow,
  TableColumnConfig, TrendByDimensionPoint, CatalogField,
} from '../../types';
import RegionSummaryGrid from '../grids/RegionSummaryGrid';
import MultiLineTrendChart from '../charts/MultiLineTrendChart';
import SpotBarChart from '../charts/SpotBarChart';
import './Dashboard.scss';

interface DashboardProps {
  params:               QueryParams;
  catalogFields:        CatalogField[];
  getRegionSummaryFlat: (p: QueryParams, field: string) => Promise<FlatRow[]>;
  getSpotData:          (p: QueryParams, field: string) => Promise<SpotRow[]>;
  getTrendByDimension:  (p: QueryParams, field: string) => Promise<TrendByDimensionPoint[]>;
}

type CardType = 'table' | 'chart' | 'spot';

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
  const mLabel = measure.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  return {
    dimensions: [{ field, headerName: fieldLabel, width: 130 }],
    measures: [
      { field: 'asofValue', headerName: `${mLabel} (AsOf)`, aggFunc: 'sum', formatter: 'currency' },
      { field: 'prevValue', headerName: `${mLabel} (Prev)`, aggFunc: 'sum', formatter: 'currency' },
      { field: 'change',    headerName: 'Change',            aggFunc: 'sum', formatter: 'currency' },
      { field: 'changePct', headerName: 'Chg %',             aggFunc: 'avg', formatter: 'percent', width: 80 },
    ],
  };
};

const buildSpotColumnConfig = (field: string, fieldLabel: string, measure: string): TableColumnConfig => {
  const mLabel = measure.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());
  return {
    dimensions: [{ field, headerName: fieldLabel, width: 130 }],
    measures: [
      { field: 'value', headerName: mLabel,   aggFunc: 'sum', formatter: 'currency' },
      { field: 'pct',   headerName: '% Total', aggFunc: 'avg', formatter: 'percent', width: 90 },
    ],
  };
};

interface PanelData {
  movementData: FlatRow[]                | null;
  spotData:     SpotRow[]                | null;
  chartData:    TrendByDimensionPoint[]  | null;
  loading:      boolean;
  error?:       string;
}

const Dashboard = ({
  params, catalogFields,
  getRegionSummaryFlat, getSpotData, getTrendByDimension,
}: DashboardProps) => {
  const { fieldConfigs, measure, chartWindow = '30d', mode } = params;
  const activeConfigs = fieldConfigs.filter(c => c.showTable || c.showChart);

  const [panelData, setPanelData] = useState<Record<string, PanelData>>({});
  const fetchGen = useRef(0);

  // Stringify params so the effect detects deep value changes, not just reference changes
  const paramsKey = JSON.stringify(params);

  useEffect(() => {
    if (activeConfigs.length === 0) return;
    const gen = ++fetchGen.current;

    const initialState: Record<string, PanelData> = {};
    for (const config of activeConfigs) {
      initialState[config.field] = { movementData: null, spotData: null, chartData: null, loading: true };
    }
    setPanelData(initialState);

    for (const config of activeConfigs) {
      const { field } = config;

      if (config.showTable) {
        const fetchTable = mode === 'spot'
          ? getSpotData(params, field)
          : getRegionSummaryFlat(params, field);

        fetchTable
          .then(data => {
            if (fetchGen.current !== gen) return;
            setPanelData(prev => ({
              ...prev,
              [field]: {
                ...prev[field],
                ...(mode === 'spot' ? { spotData: data as SpotRow[] } : { movementData: data as FlatRow[] }),
                // Stay loading if chart is also requested and hasn't arrived yet
                loading: !!(config.showChart && !prev[field]?.chartData),
              },
            }));
          })
          .catch(err => {
            if (fetchGen.current !== gen) return;
            setPanelData(prev => ({ ...prev, [field]: { ...prev[field], loading: false, error: String(err) } }));
          });
      }

      if (config.showChart) {
        getTrendByDimension(params, field)
          .then(data => {
            if (fetchGen.current !== gen) return;
            setPanelData(prev => ({
              ...prev,
              [field]: { ...prev[field], chartData: data, loading: false },
            }));
          })
          .catch(err => {
            if (fetchGen.current !== gen) return;
            setPanelData(prev => ({ ...prev, [field]: { ...prev[field], loading: false, error: String(err) } }));
          });
      }

      // If only chart (no table), set loading to false when chart arrives — already handled above.
      // If only table (no chart), set loading false immediately after table fetch. Already handled: showChart=false → loading: false
      if (config.showTable && !config.showChart) {
        // loading will be set by the table fetch via: loading: !!(config.showChart && ...)  → false
      }
    }
  }, [paramsKey]); // eslint-disable-line react-hooks/exhaustive-deps

  const getFieldLabel = (field: string) =>
    catalogFields.find(f => f.field === field)?.label ?? field;

  if (activeConfigs.length === 0) {
    return <div className="dashboard__empty">Select fields in the sidebar and click Apply</div>;
  }

  const m = measure ?? 'total_revenue';

  return (
    <div className="dashboard__flow">
      {activeConfigs.map(config => {
        const { field } = config;
        const state     = panelData[field];
        const label     = getFieldLabel(field);
        const loading   = state?.loading ?? true;

        return (
          // Key on Fragment is required so React reconciles correctly when field list changes
          <Fragment key={field}>
            {config.showTable && (
              mode === 'spot' ? (
                <DashboardCard title={`${label} — Spot`} type="spot">
                  <SpotBarChart
                    data={state?.spotData ?? []}
                    field={field}
                    fieldLabel={label}
                    measure={m}
                    loading={loading}
                  />
                </DashboardCard>
              ) : (
                <DashboardCard title={`${label} — Movement`} type="table">
                  <RegionSummaryGrid
                    data={state?.movementData ?? []}
                    loading={loading}
                    config={buildColumnConfig(field, label, m)}
                  />
                </DashboardCard>
              )
            )}

            {config.showChart && (
              <DashboardCard title={`${label} — Trend`} type="chart">
                <MultiLineTrendChart
                  data={state?.chartData ?? []}
                  field={field}
                  fieldLabel={label}
                  measure={m}
                  window={chartWindow}
                  loading={loading && !state?.chartData}
                />
              </DashboardCard>
            )}
          </Fragment>
        );
      })}
    </div>
  );
};

export default Dashboard;
