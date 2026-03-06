import { useMemo } from 'react';
import { AgGridReact } from 'ag-grid-react';
import { ColDef, ValueFormatterParams, CellClassParams, CellStyle } from 'ag-grid-community';
import { FlatRow, TableColumnConfig } from '../../types';
import 'ag-grid-community/styles/ag-grid.css';
import 'ag-grid-community/styles/ag-theme-alpine.css';
import './RegionSummaryGrid.scss';

interface RegionSummaryGridProps {
  data:    FlatRow[];
  loading: boolean;
  config:  TableColumnConfig;
}

// =============================================
// FORMATTERS
// =============================================
const formatCurrency = (p: ValueFormatterParams): string => {
  if (p.value == null || p.value === '') return '';
  return new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', minimumFractionDigits: 0,
  }).format(Number(p.value));
};

const formatCurrencyChange = (p: ValueFormatterParams): string => {
  if (p.value == null || p.value === '') return '';
  const v    = Number(p.value);
  const sign = v >= 0 ? '+' : '';
  const fmt  = new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', minimumFractionDigits: 0,
  }).format(Math.abs(v));
  return `${sign}${v < 0 ? '-' : ''}$${fmt.replace(/[$-]/g, '')}`;
};

const formatPercent = (p: ValueFormatterParams): string => {
  if (p.value == null || p.value === '') return '';
  const v = Number(p.value);
  return `${v >= 0 ? '+' : ''}${v.toFixed(1)}%`;
};

const formatNumber = (p: ValueFormatterParams): string => {
  if (p.value == null || p.value === '') return '';
  return new Intl.NumberFormat('en-US').format(Number(p.value));
};

const getFormatter = (fmt: string, field: string) => {
  if (fmt === 'percent') return formatPercent;
  if (fmt === 'number')  return formatNumber;
  if (fmt === 'currency' && field === 'change') return formatCurrencyChange;
  return formatCurrency;
};

const changeStyle = (p: CellClassParams): CellStyle => {
  if (p.value > 0) return { color: '#059669', background: 'rgba(5,150,105,0.07)', fontWeight: '600' };
  if (p.value < 0) return { color: '#DC2626', background: 'rgba(220,38,38,0.07)', fontWeight: '600' };
  return {};
};

const CHANGE_FIELDS = new Set(['change', 'changePct']);


// =============================================
// GRID
// Data is pre-aggregated per field value by
// salesService — one flat row per category.
// No rowGroup needed (Community limitation).
// =============================================
const RegionSummaryGrid = ({ data, loading, config }: RegionSummaryGridProps) => {
  const colDefs = useMemo<ColDef[]>(() => {
    // Dimension columns — shown as plain text, pinned left
    const dimCols: ColDef[] = config.dimensions.map((d, i) => ({
      field:      d.field,
      headerName: d.headerName,
      width:      d.width ?? 130,
      pinned:     i === 0 ? 'left' as const : undefined,
      sortable:   true,
      cellStyle:  { fontWeight: '600', color: '#1E40AF' },
    }));

    // Measure columns
    const measureCols: ColDef[] = config.measures.map(m => ({
      field:          m.field,
      headerName:     m.headerName,
      flex:           m.width ? undefined : 1,
      width:          m.width,
      type:           'numericColumn',
      sortable:       true,
      valueFormatter: getFormatter(m.formatter, m.field),
      cellStyle:      CHANGE_FIELDS.has(m.field) ? changeStyle : undefined,
    }));

    return [...dimCols, ...measureCols];
  }, [config]);

  const defaultColDef = useMemo<ColDef>(() => ({
    resizable: true, suppressMovable: true,
  }), []);

  if (loading) return <div className="region-grid" style={{height:120,display:"flex",alignItems:"center",justifyContent:"center",color:"#8A96A8",fontFamily:"IBM Plex Mono,monospace",fontSize:"11px"}}>Loading…</div>;

  return (
    <div className="region-grid ag-theme-alpine" style={{ width: '100%' }}>
      <AgGridReact
        rowData={data}
        columnDefs={colDefs}
        defaultColDef={defaultColDef}
        domLayout="autoHeight"
        headerHeight={32}
        rowHeight={28}
      />
    </div>
  );
};

export default RegionSummaryGrid;
