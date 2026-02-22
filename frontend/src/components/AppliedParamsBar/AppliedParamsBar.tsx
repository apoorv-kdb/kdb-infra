import { QueryParams, CatalogField } from '../../types';
import './AppliedParamsBar.scss';

interface AppliedParamsBarProps {
  params:       QueryParams;
  catalogFields: CatalogField[];
}

const Chip = ({ label }: { label: string }) => (
  <span className="applied-bar__chip">{label}</span>
);

const AppliedParamsBar = ({ params, catalogFields }: AppliedParamsBarProps) => {
  const getLabel = (field: string) =>
    catalogFields.find(f => f.field === field)?.label ?? field;

  const filters    = Object.entries(params.filters).flatMap(([k, vs]) => vs.map(v => `${k}: ${v}`));
  const exclusions = Object.entries(params.exclusions).flatMap(([k, vs]) => vs.map(v => `-${k}: ${v}`));
  const activePanels = params.fieldConfigs.filter(c => c.showTable || c.showChart);

  return (
    <div className="applied-bar">
      {params.asofDate && (
        <div className="applied-bar__group">
          <span className="applied-bar__group-label">AsOf</span>
          <Chip label={params.asofDate} />
        </div>
      )}
      {params.prevDate && (
        <div className="applied-bar__group">
          <span className="applied-bar__group-label">Prev</span>
          <Chip label={params.prevDate} />
        </div>
      )}
      {params.measure && (
        <div className="applied-bar__group">
          <span className="applied-bar__group-label">Measure</span>
          <Chip label={getLabel(params.measure)} />
        </div>
      )}
      {activePanels.length > 0 && (
        <div className="applied-bar__group">
          <span className="applied-bar__group-label">Showing</span>
          {activePanels.map(c => {
            const parts = [];
            if (c.showTable) parts.push('T');
            if (c.showChart) parts.push('C');
            return <Chip key={c.field} label={`${getLabel(c.field)} (${parts.join('+')})`} />;
          })}
        </div>
      )}
      {filters.length > 0 && (
        <div className="applied-bar__group">
          <span className="applied-bar__group-label">Filters</span>
          {filters.map(f => <Chip key={f} label={f} />)}
        </div>
      )}
      {exclusions.length > 0 && (
        <div className="applied-bar__group">
          <span className="applied-bar__group-label">Excl</span>
          {exclusions.map(f => <Chip key={f} label={f} />)}
        </div>
      )}
    </div>
  );
};

export default AppliedParamsBar;
