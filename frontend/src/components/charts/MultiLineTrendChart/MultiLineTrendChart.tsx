import { useRef, useEffect } from 'react';
import Highcharts from 'highcharts';
import HighchartsReact from 'highcharts-react-official';
import { TrendByDimensionPoint } from '../../../types';
import './MultiLineTrendChart.scss';

interface MultiLineTrendChartProps {
  data:       TrendByDimensionPoint[];
  field:      string;
  fieldLabel: string;
  measure:    string;
  window:     string;
  loading:    boolean;
}

const SERIES_COLORS = [
  '#2563EB', '#0F766E', '#B45309', '#DC2626',
  '#7C3AED', '#0369A1', '#065F46', '#92400E',
];

const formatValue = (v: number, measure: string): string => {
  if (measure.includes('revenue') || measure.includes('price')) {
    if (v >= 1_000_000) return `$${(v / 1_000_000).toFixed(1)}M`;
    if (v >= 1_000)     return `$${(v / 1_000).toFixed(0)}k`;
    return `$${v}`;
  }
  if (v >= 1_000) return `${(v / 1_000).toFixed(1)}k`;
  return String(v);
};

const BG   = '#FFFFFF';
const GRID = 'rgba(255,255,255,0.05)';
const AXIS = '#8A96A8';

const MultiLineTrendChart = ({
  data, field, fieldLabel, measure, window: win, loading,
}: MultiLineTrendChartProps) => {
  const chartRef = useRef<HighchartsReact.RefObject>(null);

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
    marker:    { enabled: true, radius: 3, symbol: 'circle' },
    lineWidth: 2,
  }));

  const options: Highcharts.Options = {
    chart: {
      type:            'line',
      backgroundColor: BG,
      style:           { fontFamily: "'IBM Plex Mono', monospace" },
      height:          240,
      animation:       { duration: 350 },
      margin:          [8, 12, 68, 46],
    },
    title:    { text: undefined },
    subtitle: {
      text: `WINDOW: ${win}`,
      align: 'right',
      style: { fontSize: '10px', color: AXIS, fontFamily: "'IBM Plex Mono', monospace", letterSpacing: '0.5px' },
    },
    credits: { enabled: false },
    legend: {
      enabled:      true,
      align:        'center',
      verticalAlign:'bottom',
      itemStyle:    { fontSize: '10px', fontWeight: '500', color: AXIS, fontFamily: "'IBM Plex Mono', monospace" },
      itemHoverStyle: { color: '#2563EB' },
      symbolRadius: 3,
      margin:       12,
    },
    xAxis: {
      categories: dates.map(d => {
        const dt = new Date(d);
        return dt.toLocaleDateString('en-US', { day: '2-digit', month: 'short' });
      }),
      labels: {
        style: { fontSize: '9px', color: AXIS, fontFamily: "'IBM Plex Mono', monospace" },
        rotation: -45,
        align: 'right',
        step: Math.max(1, Math.floor(dates.length / 12)),  // max ~12 labels
      },
      lineColor:     GRID,
      tickColor:     GRID,
      gridLineColor: 'transparent',
    },
    yAxis: {
      title:  { text: undefined },
      labels: {
        style:     { fontSize: '10px', color: AXIS, fontFamily: "'IBM Plex Mono', monospace" },
        formatter: function () { return formatValue(this.value as number, measure); },
      },
      gridLineColor:     GRID,
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
              <td style="padding:2px 10px 2px 0">
                <span style="color:${p.color};font-size:12px;line-height:1">●</span>
                <span style="color:#4A5568;font-size:10px;font-family:'IBM Plex Mono',monospace"> ${p.series.name}</span>
              </td>
              <td style="text-align:right;font-weight:600;font-size:10px;color:#1E2A3D;font-family:'IBM Plex Mono',monospace">
                ${formatValue(p.y ?? 0, measure)}
              </td>
            </tr>
          `).join('');
        return `
          <div style="padding:4px 2px">
            <div style="font-size:10px;color:#8A96A8;margin-bottom:5px;padding-bottom:4px;border-bottom:1px solid #E2E6ED;font-family:'IBM Plex Mono',monospace">${this.x}</div>
            <table>${rows}</table>
          </div>`;
      },
      backgroundColor: '#FFFFFF',
      borderColor:     '#E2E6ED',
      borderRadius:    4,
      shadow:          true,
      style:           { boxShadow: '0 2px 8px rgba(0,0,0,0.09)' },
    },
    plotOptions: { line: { animation: { duration: 350 } } },
    series,
  };

  if (loading) return <div className="multi-trend__loading">Loading…</div>;
  if (data.length === 0) return <div className="multi-trend__empty">No data for this window</div>;

  return (
    <div className="multi-trend">
      <HighchartsReact highcharts={Highcharts} options={options} ref={chartRef} />
    </div>
  );
};

export default MultiLineTrendChart;
