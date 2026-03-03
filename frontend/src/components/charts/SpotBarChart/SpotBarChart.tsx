import { useRef, useEffect } from 'react';
import Highcharts from 'highcharts';
import HighchartsReact from 'highcharts-react-official';
import { SpotRow } from '../../../types';
import './SpotBarChart.scss';

interface SpotBarChartProps {
  data:       SpotRow[];
  field:      string;
  fieldLabel: string;
  measure:    string;
  loading:    boolean;
}

const BAR_COLORS = ['#2563EB','#0F766E','#B45309','#7C3AED','#DC2626','#0369A1','#065F46','#92400E'];
const BG   = '#FFFFFF';
const AXIS = '#8A96A8';
const GRID = 'rgba(255,255,255,0.06)';

const formatValue = (v: number, measure: string): string => {
  if (measure.includes('revenue') || measure.includes('price')) {
    if (v >= 1_000_000) return `$${(v / 1_000_000).toFixed(1)}M`;
    if (v >= 1_000)     return `$${(v / 1_000).toFixed(0)}k`;
    return `$${v}`;
  }
  if (v >= 1_000) return `${(v / 1_000).toFixed(1)}k`;
  return String(v);
};

const SpotBarChart = ({ data, field, fieldLabel, measure, loading }: SpotBarChartProps) => {
  const chartRef = useRef<HighchartsReact.RefObject>(null);

  if (loading) return <div className="spot-chart__empty">Loading…</div>;
  if (data.length === 0) return <div className="spot-chart__empty">No data</div>;

  const categories = data.map(r => String(r[field] ?? ''));
  const values     = data.map(r => r.value);
  const pcts       = data.map(r => +(r.pct * 100).toFixed(1));

  const options: Highcharts.Options = {
    chart: {
      type:            'bar',
      backgroundColor: BG,
      style:           { fontFamily: "'IBM Plex Mono', monospace" },
      height:          Math.max(130, data.length * 28 + 36),
      animation:       { duration: 350 },
      margin:          [8, 16, 28, 75],
    },
    title:    { text: undefined },
    credits:  { enabled: false },
    legend:   { enabled: false },
    xAxis: {
      categories,
      labels: { style: { fontSize: '11px', color: AXIS, fontFamily: "'IBM Plex Mono', monospace" } },
      lineColor: GRID,
      tickColor: GRID,
    },
    yAxis: {
      title:  { text: undefined },
      labels: {
        style:     { fontSize: '10px', color: AXIS, fontFamily: "'IBM Plex Mono', monospace" },
        formatter: function () { return formatValue(this.value as number, measure); },
      },
      gridLineColor: GRID,
      gridLineDashStyle: 'Dash',
    },
    tooltip: {
      useHTML:   true,
      formatter: function () {
        const idx   = this.point.index;
        const pct   = pcts[idx];
        const color = BAR_COLORS[idx % BAR_COLORS.length];
        return `
          <div style="padding:6px 8px;background:#FFFFFF;border-radius:4px;font-family:'IBM Plex Mono',monospace">
            <span style="color:${color};font-size:12px">●</span>
            <span style="color:#4A5568;font-size:10px"> ${this.key}</span><br/>
            <span style="color:#1E2A3D;font-size:11px;font-weight:600">${formatValue(this.y ?? 0, measure)}</span>
            <span style="color:#8A96A8;font-size:10px"> · ${pct}%</span>
          </div>`;
      },
      backgroundColor: '#FFFFFF',
      borderColor:     '#E2E6ED',
      borderRadius:    4,
      shadow:          true,
    },
    plotOptions: {
      bar: {
        borderRadius: 3,
        colorByPoint: true,
        colors:       BAR_COLORS,
        dataLabels: {
          enabled:   true,
          formatter: function () { return `${pcts[this.point.index]}%`; },
          style:     {
            fontSize:    '10px',
            color:       '#4A5568',
            fontFamily:  "'IBM Plex Mono', monospace",
            fontWeight:  '500',
            textOutline: 'none',
          },
        },
      },
    },
    series: [{ type: 'bar', name: fieldLabel, data: values }],
  };

  return (
    <div className="spot-chart">
      <HighchartsReact highcharts={Highcharts} options={options} ref={chartRef} />
    </div>
  );
};

export default SpotBarChart;
