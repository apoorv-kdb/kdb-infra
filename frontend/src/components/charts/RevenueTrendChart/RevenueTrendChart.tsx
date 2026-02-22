import HighchartsReact from 'highcharts-react-official';
import Highcharts from 'highcharts';
import { TrendPoint } from '../../../types';
import './RevenueTrendChart.scss';

interface RevenueTrendChartProps {
  data:    TrendPoint[];
  window:  string;
  loading: boolean;
}

// ---- Shared chart styling ----
// Applied to both charts to align with our Material palette

export const CHART_COLORS = {
  primary:    '#1976D2',   // blue-700
  secondary:  '#42A5F5',   // blue-400
  positive:   '#43A047',
  negative:   '#E53935',
  gridLine:   '#E0E0E0',
  axisLabel:  '#757575',
  tooltip:    '#FFFFFF',
};

const RevenueTrendChart = ({ data, window, loading }: RevenueTrendChartProps) => {

  // Highcharts expects [timestamp, value] pairs for time series
  const seriesData = data.map(point => [
    new Date(point.date).getTime(),
    point.revenue,
  ]);

  const options: Highcharts.Options = {
    chart: {
      type: 'line',
      backgroundColor: '#FFFFFF',
      style: { fontFamily: "-apple-system, 'Segoe UI', sans-serif" },
      height: 280,
      animation: { duration: 400 },
    },

    title: { text: undefined },   // title lives in the DashboardCard header

    credits: { enabled: false },  // removes Highcharts watermark

    xAxis: {
      type: 'datetime',
      labels: {
        style: { color: CHART_COLORS.axisLabel, fontSize: '12px' },
        format: '{value:%d %b}',
      },
      lineColor: CHART_COLORS.gridLine,
      tickColor: CHART_COLORS.gridLine,
    },

    yAxis: {
      title: { text: undefined },
      labels: {
        style: { color: CHART_COLORS.axisLabel, fontSize: '12px' },
        // Format y-axis ticks as $120k instead of 120000
        formatter() {
          const v = this.value as number;
          if (v >= 1_000_000) return `$${(v / 1_000_000).toFixed(1)}M`;
          if (v >= 1_000)     return `$${(v / 1_000).toFixed(0)}k`;
          return `$${v}`;
        },
      },
      gridLineColor: CHART_COLORS.gridLine,
    },

    tooltip: {
      backgroundColor: '#FFFFFF',
      borderColor: '#E0E0E0',
      borderRadius: 8,
      shadow: true,
      style: { color: '#212121', fontSize: '13px' },
      xDateFormat: '%d %b %Y',
      // Format tooltip value as full currency
      pointFormatter() {
        return `<span style="color:${this.color}">●</span> Revenue: <b>$${
          (this.y as number).toLocaleString()
        }</b><br/>`;
      },
    },

    legend: { enabled: false },

    series: [{
      type: 'line',
      name: 'Revenue',
      data: seriesData,
      color: CHART_COLORS.primary,
      lineWidth: 2,
      marker: {
        enabled: true,      // data point markers
        radius: 4,
        symbol: 'circle',
        fillColor: '#FFFFFF',
        lineColor: CHART_COLORS.primary,
        lineWidth: 2,
      },
      states: {
        hover: {
          lineWidth: 3,
          marker: { radius: 6 },
        },
      },
    }],

    responsive: {
      rules: [{
        condition: { maxWidth: 500 },
        chartOptions: {
          xAxis: { labels: { rotation: -45 } },
        },
      }],
    },
  };

  if (loading) {
    return <div className="trend-chart__loading">Loading...</div>;
  }

  return (
    <div className="trend-chart">
      <div className="trend-chart__window-label">Window: {window}</div>
      <HighchartsReact highcharts={Highcharts} options={options} />
    </div>
  );
};

export default RevenueTrendChart;
