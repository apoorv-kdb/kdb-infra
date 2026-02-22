import { useMemo, useState } from 'react';
import { AgGridReact } from 'ag-grid-react';
import { ColDef, ValueFormatterParams, themeQuartz } from 'ag-grid-community';
import { Transaction } from '../../../types';
import 'ag-grid-community/styles/ag-grid.css';
import './TransactionGrid.scss';

interface TransactionGridProps {
  data:    Transaction[];
  loading: boolean;
}

const formatDate = (p: ValueFormatterParams): string =>
  p.value ? new Date(p.value).toLocaleDateString('en-US', {
    year: 'numeric', month: 'short', day: 'numeric',
  }) : '';

const formatRevenue = (p: ValueFormatterParams): string =>
  p.value == null ? '' : new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD', minimumFractionDigits: 0,
  }).format(p.value);

const formatQuantity = (p: ValueFormatterParams): string =>
  p.value == null ? '' : new Intl.NumberFormat('en-US').format(p.value);

const gridTheme = themeQuartz.withParams({
  fontFamily: "-apple-system, 'Segoe UI', sans-serif",
  fontSize: 12,
  rowHeight: 28,
  headerHeight: 32,
  borderColor: '#E0E0E0',
  rowHoverColor: '#E3F2FD',
  selectedRowBackgroundColor: '#BBDEFB',
  accentColor: '#1976D2',
  oddRowBackgroundColor: '#F8FAFD',
});

const PAGE_SIZE = 50;

const TransactionGrid = ({ data, loading }: TransactionGridProps) => {
  const [currentPage, setCurrentPage] = useState(0);
  const totalPages = Math.ceil(data.length / PAGE_SIZE);

  const colDefs = useMemo<ColDef<Transaction>[]>(() => [
    { field: 'date',     headerName: 'Date',     width: 120, valueFormatter: formatDate,     sortable: true },
    { field: 'region',   headerName: 'Region',   width: 90,  sortable: true, filter: 'agTextColumnFilter', floatingFilter: true },
    { field: 'product',  headerName: 'Product',  flex: 1,    sortable: true, filter: 'agTextColumnFilter', floatingFilter: true },
    { field: 'quantity', headerName: 'Qty',      width: 90,  valueFormatter: formatQuantity, sortable: true, type: 'numericColumn' },
    { field: 'revenue',  headerName: 'Revenue',  width: 120, valueFormatter: formatRevenue,  sortable: true, type: 'numericColumn' },
  ], []);

  const defaultColDef = useMemo<ColDef>(() => ({
    resizable: true, suppressMovable: true,
  }), []);

  return (
    <div className="transaction-grid">
      <AgGridReact
        theme={gridTheme}
        rowData={data}
        columnDefs={colDefs}
        defaultColDef={defaultColDef}
        loading={loading}
        pagination={true}
        paginationPageSize={PAGE_SIZE}
        onPaginationChanged={e => setCurrentPage(e.api.paginationGetCurrentPage())}
        domLayout="autoHeight"
        headerHeight={32}
        rowHeight={28}
        animateRows={true}
      />
      {!loading && data.length > 0 && (
        <div className="transaction-grid__footer">
          <span>{data.length.toLocaleString()} rows</span>
          <span>Page {currentPage + 1} of {totalPages}</span>
        </div>
      )}
    </div>
  );
};

export default TransactionGrid;
