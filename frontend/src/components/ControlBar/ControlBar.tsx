import { useState } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import {
  faPlay, faFloppyDisk, faChevronDown, faTrash,
  faStar as faSolidStar, faPencil, faChevronUp,
} from '@fortawesome/free-solid-svg-icons';
import { faStar as faRegularStar } from '@fortawesome/free-regular-svg-icons';
import { Preset, ControlBarState, QueryParams } from '../../types';
import { groupPresets } from '../../hooks/usePresets';
import PresetSaveModal from '../shared/PresetSaveModal/PresetSaveModal';
import './ControlBar.scss';

interface ControlBarProps {
  // Row 1 children (dates, tables, charts, window)
  row1Children:   React.ReactNode;
  // Row 2 children (filters, exclusions)
  row2Children:   React.ReactNode;
  onApply:        () => void;
  // Collapsed summary
  appliedParams:  QueryParams | null;
  // Preset props
  presets:        Preset[];
  currentState:   ControlBarState;
  onSavePreset:   (name: string, group: string) => void;
  onLoadPreset:   (preset: Preset) => void;
  onDeletePreset: (id: string) => void;
  onSetDefault:   (id: string) => void;
}

const formatSummary = (params: QueryParams): string => {
  const parts: string[] = [];
  if (params.asofDate) parts.push(`AsOf: ${params.asofDate}`);
  if (params.prevDate) parts.push(`Prev: ${params.prevDate}`);
  const filters = Object.entries(params.filters).flatMap(([k, vs]) => vs.map(v => `${k}:${v}`));
  if (filters.length) parts.push(`Filters: ${filters.join(', ')}`);
  const excl = Object.entries(params.exclusions).flatMap(([k, vs]) => vs.map(v => `-${k}:${v}`));
  if (excl.length) parts.push(`Excl: ${excl.join(', ')}`);
  return parts.join('  |  ') || 'No filters applied';
};

const ControlBar = ({
  row1Children, row2Children, onApply, appliedParams,
  presets, currentState, onSavePreset, onLoadPreset, onDeletePreset, onSetDefault,
}: ControlBarProps) => {
  const [collapsed,      setCollapsed]      = useState(false);
  const [showSaveModal,  setShowSaveModal]  = useState(false);
  const [showPresetMenu, setShowPresetMenu] = useState(false);

  const grouped = groupPresets(presets);
  const groupNames = Object.keys(grouped).sort();

  const handleApply = () => {
    onApply();
    setCollapsed(true);
  };

  const handleSave = (name: string, group: string) => {
    onSavePreset(name, group);
    setShowSaveModal(false);
  };

  // Collapsed state — slim summary strip
  if (collapsed && appliedParams) {
    return (
      <div className="control-bar control-bar--collapsed">
        <div className="control-bar__summary-text">
          {formatSummary(appliedParams)}
        </div>
        <button
          className="control-bar__edit-btn"
          onClick={() => setCollapsed(false)}
        >
          <FontAwesomeIcon icon={faPencil} />
          Edit
        </button>
      </div>
    );
  }

  return (
    <div className="control-bar">
      {/* Row 1: dates, selectors, actions */}
      <div className="control-bar__row control-bar__row--1">
        <div className="control-bar__fields">
          {row1Children}
        </div>
        <div className="control-bar__actions">
          <div className="control-bar__preset-wrapper">
            <button
              className="control-bar__btn control-bar__btn--secondary"
              onClick={() => setShowPresetMenu(o => !o)}
            >
              <FontAwesomeIcon icon={faFloppyDisk} />
              Presets
              <FontAwesomeIcon icon={faChevronDown} className="control-bar__btn-chevron" />
            </button>

            {showPresetMenu && (
              <div className="control-bar__preset-menu">
                {groupNames.length === 0 ? (
                  <div className="control-bar__preset-empty">No saved presets</div>
                ) : (
                  groupNames.map(groupName => (
                    <div key={groupName}>
                      <div className="control-bar__preset-group-label">{groupName}</div>
                      {grouped[groupName].map(preset => (
                        <div key={preset.id} className="control-bar__preset-item">
                          <button
                            className={`control-bar__preset-star ${preset.isDefault ? 'control-bar__preset-star--active' : ''}`}
                            onClick={() => onSetDefault(preset.id)}
                            title={preset.isDefault ? 'Remove default' : 'Set as default'}
                          >
                            <FontAwesomeIcon icon={preset.isDefault ? faSolidStar : faRegularStar} />
                          </button>
                          <span
                            className="control-bar__preset-name"
                            onClick={() => { onLoadPreset(preset); setShowPresetMenu(false); }}
                          >
                            {preset.name}
                            {preset.isDefault && <span className="control-bar__preset-default-badge">default</span>}
                          </span>
                          <button
                            className="control-bar__preset-delete"
                            onClick={() => onDeletePreset(preset.id)}
                          >
                            <FontAwesomeIcon icon={faTrash} />
                          </button>
                        </div>
                      ))}
                    </div>
                  ))
                )}
                <div className="control-bar__preset-divider" />
                <div
                  className="control-bar__preset-save-action"
                  onClick={() => { setShowPresetMenu(false); setShowSaveModal(true); }}
                >
                  <FontAwesomeIcon icon={faFloppyDisk} />
                  Save current as preset...
                </div>
              </div>
            )}
          </div>

          <button className="control-bar__btn control-bar__btn--primary" onClick={handleApply}>
            <FontAwesomeIcon icon={faPlay} />
            Apply
          </button>

          {appliedParams && (
            <button
              className="control-bar__btn control-bar__btn--icon"
              onClick={() => setCollapsed(true)}
              title="Collapse"
            >
              <FontAwesomeIcon icon={faChevronUp} />
            </button>
          )}
        </div>
      </div>

      {/* Row 2: filters and exclusions */}
      <div className="control-bar__row control-bar__row--2">
        {row2Children}
      </div>

      {showSaveModal && (
        <PresetSaveModal
          onSave={handleSave}
          onCancel={() => setShowSaveModal(false)}
        />
      )}
    </div>
  );
};

export default ControlBar;
