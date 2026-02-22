import { useEffect, useRef } from 'react';
import Highcharts from 'highcharts';
import HighchartsReact from 'highcharts-react-official';
import { TrendByDimensionPoint } from '../../../types';
import './MultiLineTrendChart.scss';

interface MultiLineTrendChartProps {
  data:       TrendByDimensionPoint[];
  field:      string;   // dimension name e.g. 'region'
  fieldLabel: string;   // e.g. 'Region'
  measure:    string;   // e.g. 'revenue'
  window:     string;
  loading:    boolean;
}

// Teal-to-blue palette — distinct, professional
const SERIES_COLORS = [
  '#1976D2', // blue
  '#00838F', // teal
  '#7B1FA2', // purple
  '#E65100', // deep orange
  '#2E7D32', // green
  '#C62828', // red
  '#F57F17', // amber
  '#37474F', // slate
];

const formatValue = (v: number, measure: string): string => {
  if (measure === 'revenue' || measure === 'price') {
    if (v >= 1000000) return `$${(v / 1000000).toFixed(1)}M`;
    if (v >= 1000)    return `$${(v / 1000).toFixed(0)}k`;
    return `$${v}`;
  }
  if (v >= 1000) return `${(v / 1000).toFixed(1)}k`;
  return String(v);
};

const MultiLineTrendChart = ({
  data, field, fieldLabel, measure, window: win, loading,
}: MultiLineTrendChartProps) => {
  const chartRef = useRef<HighchartsReact.RefObject>(null);

  // Pivot flat data → Highcharts series
  const dates      = [...new Set(data.map(d => d.date))].sort();
  const categories = [...new Set(data.map(d => d.category))].sort();

  const series: Highcharts.SeriesLineOptions[] = categories.map((cat, i) => ({
    type:  'line',
    name:  cat,
    color: SERIES_COLORS[i % SERIES_COLORS.length],
    data:  dates.map(date => {
      const pt = data.find(d => d.date === date && d.category === cat);
      return pt ? pt.value : null;
    }),
    marker: { enabled: true, radius: 3 },
    lineWidth: 2,
  }));

  const options: Highcharts.Options = {
    chart: {
      type:            'line',
      backgroundColor: 'transparent',
      style:           { fontFamily: "-apple-system, 'Segoe UI', sans-serif" },
      height:          260,
      animation:       { duration: 400 },
    },
    title:    { text: undefined },
    subtitle: { text: `WINDOW: ${win}`, align: 'right', style: { fontSize: '10px', color: '#9E9E9E' } },
    credits:  { enabled: false },
    legend: {
      enabled:     true,
      align:       'right',
      verticalAlign:'top',
      itemStyle:   { fontSize: '11px', fontWeight: '500', color: '#424242' },
      symbolRadius: 4,
    },
    xAxis: {
      categories: dates.map(d => {
        const dt = new Date(d);
        return dt.toLocaleDateString('en-US', { day: '2-digit', month: 'short' });
      }),
      labels: { style: { fontSize: '10px', color: '#757575' } },
      lineColor:  '#E0E0E0',
      tickColor:  '#E0E0E0',
      gridLineColor: 'transparent',
    },
    yAxis: {
      title:  { text: undefined },
      labels: {
        style:     { fontSize: '10px', color: '#757575' },
        formatter: function () { return formatValue(this.value as number, measure); },
      },
      gridLineColor: '#F5F5F5',
      gridLineDashStyle: 'Dash',
    },
    tooltip: {
      shared:    true,
      useHTML:   true,
      formatter: function () {
        const pts = (this.points ?? []);
        const rows = pts
          .sort((a, b) => (b.y ?? 0) - (a.y ?? 0))
          .map(p => `
            <tr>
              <td style="padding:2px 8px 2px 0">
                <span style="color:${p.color};font-size:16px;line-height:1">●</span>
                <span style="color:#424242;font-size:11px"> ${p.series.name}</span>
              </td>
              <td style="text-align:right;font-weight:600;font-size:11px;color:#212121">
                ${formatValue(p.y ?? 0, measure)}
              </td>
            </tr>
          `).join('');
        return `
          <div style="padding:6px 4px">
            <div style="font-size:11px;color:#757575;margin-bottom:6px">${this.x}</div>
            <table>${rows}</table>
          </div>`;
      },
      backgroundColor: 'white',
      borderColor:     '#E0E0E0',
      borderRadius:    6,
      shadow:          { color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 2, opacity: 1, width: 8 },
    },
    plotOptions: {
      line: {
        animation: { duration: 400 },
      },
    },
    series,
  };

  if (loading) {
    return <div className="multi-trend__loading">Loading...</div>;
  }

  if (data.length === 0) {
    return <div className="multi-trend__empty">No data</div>;
  }

  return (
    <div className="multi-trend">
      <HighchartsReact highcharts={Highcharts} options={options} ref={chartRef} />
    </div>
  );
};

export default MultiLineTrendChart;
