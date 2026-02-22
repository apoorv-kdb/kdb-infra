import HighchartsReact from 'highcharts-react-official';
import Highcharts from 'highcharts';
import { RegionSummary } from '../../../types';
import { CHART_COLORS } from '../RevenueTrendChart/RevenueTrendChart';
import './RevenueByRegionChart.scss';

interface RevenueByRegionChartProps {
  data:    RegionSummary[];
  loading: boolean;
}

const RevenueByRegionChart = ({ data, loading }: RevenueByRegionChartProps) => {

  // Extract categories and series data from RegionSummary rows
  const categories  = data.map(d => d.region);
  const asofValues  = data.map(d => d.asofRevenue);
  const prevValues  = data.map(d => d.prevRevenue);

  const options: Highcharts.Options = {
    chart: {
      type: 'column',      // Highcharts calls bar charts "column" for vertical bars
      backgroundColor: '#FFFFFF',
      style: { fontFamily: "-apple-system, 'Segoe UI', sans-serif" },
      height: 280,
      animation: { duration: 400 },
    },

    title: { text: undefined },
    credits: { enabled: false },

    xAxis: {
      categories,
      labels: {
        style: { color: CHART_COLORS.axisLabel, fontSize: '12px' },
      },
      lineColor: CHART_COLORS.gridLine,
      tickColor: CHART_COLORS.gridLine,
    },

    yAxis: {
      title: { text: undefined },
      labels: {
        style: { color: CHART_COLORS.axisLabel, fontSize: '12px' },
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
      shared: true,        // shows both series in one tooltip on hover
      backgroundColor: '#FFFFFF',
      borderColor: '#E0E0E0',
      borderRadius: 8,
      shadow: true,
      style: { color: '#212121', fontSize: '13px' },
      pointFormatter() {
        return `<span style="color:${this.color}">●</span> ${this.series.name}: <b>$${
          (this.y as number).toLocaleString()
        }</b><br/>`;
      },
    },

    legend: {
      enabled: true,
      align: 'right',
      verticalAlign: 'top',
      itemStyle: {
        color: '#616161',
        fontSize: '12px',
        fontWeight: '500',
      },
    },

    plotOptions: {
      column: {
        grouping: true,     // side-by-side grouped bars
        borderWidth: 0,
        borderRadius: 3,
        pointPadding: 0.1,
        groupPadding: 0.2,
      },
    },

    series: [
      {
        type: 'column',
        name: 'AsOf',
        data: asofValues,
        color: CHART_COLORS.primary,
      },
      {
        type: 'column',
        name: 'Prev',
        data: prevValues,
        color: CHART_COLORS.secondary,
      },
    ],
  };

  if (loading) {
    return <div className="region-chart__loading">Loading...</div>;
  }

  return (
    <div className="region-chart">
      <HighchartsReact highcharts={Highcharts} options={options} />
    </div>
  );
};

export default RevenueByRegionChart;
