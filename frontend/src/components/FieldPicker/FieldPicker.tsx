import { useRef, useState } from 'react';
import { CatalogField, FieldConfig } from '../../types';
import './FieldPicker.scss';

interface FieldPickerProps {
  fields:       CatalogField[];
  measure:      string | null;
  fieldConfigs: FieldConfig[];
  onMeasureChange:      (field: string) => void;
  onFieldConfigsChange: (configs: FieldConfig[]) => void;
}

const FieldPicker = ({
  fields, measure, fieldConfigs,
  onMeasureChange, onFieldConfigsChange,
}: FieldPickerProps) => {
  const categoricals = fields.filter(f => f.fieldType === 'categorical');
  const values       = fields.filter(f => f.fieldType === 'value');

  const dragItem     = useRef<number | null>(null);
  const dragOverItem = useRef<number | null>(null);
  const [dragging,   setDragging] = useState<number | null>(null);

  // Get or create FieldConfig for a field
  const getConfig = (field: string): FieldConfig =>
    fieldConfigs.find(c => c.field === field) ?? { field, showTable: false, showChart: false };

  const updateConfig = (field: string, patch: Partial<FieldConfig>) => {
    const existing = fieldConfigs.find(c => c.field === field);
    if (existing) {
      const updated = fieldConfigs.map(c =>
        c.field === field ? { ...c, ...patch } : c
      );
      // Remove if both unchecked
      onFieldConfigsChange(updated.filter(c => c.showTable || c.showChart));
    } else {
      // Add new config
      onFieldConfigsChange([...fieldConfigs, { field, showTable: false, showChart: false, ...patch }]);
    }
  };

  // Active = at least one of table/chart checked
  const activeFields   = fieldConfigs.filter(c => c.showTable || c.showChart).map(c => c.field);
  const inactiveFields = categoricals.filter(c => !activeFields.includes(c.field));

  const handleDragStart = (index: number) => {
    dragItem.current = index;
    setDragging(index);
  };

  const handleDragEnter = (index: number) => {
    dragOverItem.current = index;
  };

  const handleDragEnd = () => {
    if (dragItem.current === null || dragOverItem.current === null) {
      setDragging(null);
      return;
    }
    const reordered = [...fieldConfigs];
    const [moved]   = reordered.splice(dragItem.current, 1);
    reordered.splice(dragOverItem.current, 0, moved);
    onFieldConfigsChange(reordered);
    dragItem.current     = null;
    dragOverItem.current = null;
    setDragging(null);
  };

  return (
    <div className="field-picker">

      {/* MEASURE */}
      <div className="field-picker__section">
        <div className="field-picker__section-label">Measure</div>
        <div className="field-picker__measure-list">
          {values.map(v => (
            <label key={v.field} className="field-picker__measure-item">
              <input
                type="radio"
                name="measure"
                value={v.field}
                checked={measure === v.field}
                onChange={() => onMeasureChange(v.field)}
                className="field-picker__radio"
              />
              <span className="field-picker__measure-label">{v.label}</span>
            </label>
          ))}
        </div>
      </div>

      {/* GROUP BY */}
      <div className="field-picker__section">
        <div className="field-picker__section-label">
          <span className="field-picker__section-label-text">Group By</span>
          <span className="field-picker__col-headers">
            <span>Table</span>
            <span>Chart</span>
          </span>
        </div>

        <div className="field-picker__groupby-list">

          {/* Active fields — draggable */}
          {fieldConfigs.filter(c => c.showTable || c.showChart).map((config, index) => {
            const cat = categoricals.find(c => c.field === config.field);
            if (!cat) return null;
            return (
              <div
                key={config.field}
                className={`field-picker__row field-picker__row--active ${dragging === index ? 'field-picker__row--dragging' : ''}`}
                draggable
                onDragStart={() => handleDragStart(index)}
                onDragEnter={() => handleDragEnter(index)}
                onDragEnd={handleDragEnd}
                onDragOver={e => e.preventDefault()}
              >
                <span className="field-picker__drag-handle">≡</span>
                <span className="field-picker__field-label">{cat.label}</span>
                <div className="field-picker__checks">
                  <input
                    type="checkbox"
                    checked={config.showTable}
                    onChange={e => updateConfig(config.field, { showTable: e.target.checked })}
                    className="field-picker__checkbox"
                    title="Show table"
                  />
                  <input
                    type="checkbox"
                    checked={config.showChart}
                    onChange={e => updateConfig(config.field, { showChart: e.target.checked })}
                    className="field-picker__checkbox"
                    title="Show chart"
                  />
                </div>
              </div>
            );
          })}

          {/* Divider */}
          {activeFields.length > 0 && inactiveFields.length > 0 && (
            <div className="field-picker__divider" />
          )}

          {/* Inactive fields */}
          {inactiveFields.map(cat => {
            const config = getConfig(cat.field);
            return (
              <div key={cat.field} className="field-picker__row field-picker__row--inactive">
                <span className="field-picker__drag-handle field-picker__drag-handle--hidden">≡</span>
                <span className="field-picker__field-label">{cat.label}</span>
                <div className="field-picker__checks">
                  <input
                    type="checkbox"
                    checked={false}
                    onChange={e => updateConfig(cat.field, { showTable: e.target.checked })}
                    className="field-picker__checkbox"
                    title="Show table"
                  />
                  <input
                    type="checkbox"
                    checked={false}
                    onChange={e => updateConfig(cat.field, { showChart: e.target.checked })}
                    className="field-picker__checkbox"
                    title="Show chart"
                  />
                </div>
              </div>
            );
          })}

        </div>
      </div>
    </div>
  );
};

export default FieldPicker;
