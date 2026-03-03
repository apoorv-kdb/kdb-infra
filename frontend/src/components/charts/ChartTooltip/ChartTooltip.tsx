import './ChartTooltip.scss';

interface TooltipEntry {
  dataKey: string;
  name:    string;
  value:   number;
  color:   string;
}

interface ChartTooltipProps {
  active?:    boolean;
  payload?:   TooltipEntry[];
  label?:     string;
  formatter?: (value: number) => string;
}

const defaultFormatter = (value: number): string =>
  value >= 1000 ? value.toLocaleString(undefined, { maximumFractionDigits: 1 }) : String(value);

const ChartTooltip = ({ active, payload, label, formatter = defaultFormatter }: ChartTooltipProps) => {
  if (!active || !payload?.length) return null;

  return (
    <div className="chart-tooltip">
      {label && <div className="chart-tooltip__label">{label}</div>}
      {payload.map((entry, i) => (
        <div key={i} className="chart-tooltip__row">
          <span className="chart-tooltip__dot" style={{ background: entry.color }} />
          <span className="chart-tooltip__name">{entry.name}</span>
          <span className="chart-tooltip__value">{formatter(entry.value)}</span>
        </div>
      ))}
    </div>
  );
};

export default ChartTooltip;
