import { useState } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import {
  faPlay, faFloppyDisk, faChevronDown, faTrash,
  faStar as faSolidStar, faChevronLeft, faChevronRight,
} from '@fortawesome/free-solid-svg-icons';
import { faStar as faRegularStar } from '@fortawesome/free-regular-svg-icons';
import { Preset, ControlBarState, CatalogField } from '../../types';
import { groupPresets } from '../../hooks/usePresets';
import PresetSaveModal from '../shared/PresetSaveModal/PresetSaveModal';
import FieldPicker from '../FieldPicker/FieldPicker';
import './ControlSidebar.scss';

interface ControlSidebarProps {
  collapsed:         boolean;
  onToggleCollapse:  () => void;
  draft:             ControlBarState;
  onFieldChange:     <K extends keyof ControlBarState>(key: K, value: ControlBarState[K]) => void;
  onApply:           () => void;
  datePickerAsof:    React.ReactNode;
  datePickerPrev:    React.ReactNode;
  windowSelector:    React.ReactNode;
  filterDropdown:    React.ReactNode;
  exclusionDropdown: React.ReactNode;
  catalogFields:     CatalogField[];
  presets:           Preset[];
  onSavePreset:      (name: string, group: string) => void;
  onLoadPreset:      (preset: Preset) => void;
  onDeletePreset:    (id: string) => void;
  onSetDefault:      (id: string) => void;
}

const Section = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <div className="ctrl-sidebar__section">
    <div className="ctrl-sidebar__section-label">{label}</div>
    <div className="ctrl-sidebar__section-body">{children}</div>
  </div>
);

const ControlSidebar = ({
  collapsed, onToggleCollapse,
  draft, onFieldChange, onApply,
  datePickerAsof, datePickerPrev,
  windowSelector, filterDropdown, exclusionDropdown,
  catalogFields,
  presets, onSavePreset, onLoadPreset, onDeletePreset, onSetDefault,
}: ControlSidebarProps) => {
  const [showSaveModal,  setShowSaveModal]  = useState(false);
  const [showPresetMenu, setShowPresetMenu] = useState(false);

  const grouped    = groupPresets(presets);
  const groupNames = Object.keys(grouped).sort();

  const handleSave = (name: string, group: string) => {
    onSavePreset(name, group);
    setShowSaveModal(false);
  };

  return (
    <>
      <aside className={`ctrl-sidebar ${collapsed ? 'ctrl-sidebar--collapsed' : ''}`}>
        <button className="ctrl-sidebar__toggle" onClick={onToggleCollapse}>
          <FontAwesomeIcon icon={collapsed ? faChevronRight : faChevronLeft} />
        </button>

        {!collapsed && (
          <div className="ctrl-sidebar__content">

            <Section label="Dates">
              <div className="ctrl-sidebar__row">
                {datePickerAsof}
                {datePickerPrev}
              </div>
            </Section>

            <Section label="Filters">
              {filterDropdown}
            </Section>

            <Section label="Exclusions">
              {exclusionDropdown}
            </Section>

            <Section label="Window">
              {windowSelector}
            </Section>

            <Section label="Fields">
              <FieldPicker
                fields={catalogFields}
                measure={draft.measure}
                fieldConfigs={draft.fieldConfigs}
                onMeasureChange={v => onFieldChange('measure', v)}
                onFieldConfigsChange={v => onFieldChange('fieldConfigs', v)}
              />
            </Section>

            <div className="ctrl-sidebar__spacer" />

            {/* PRESETS */}
            <div className="ctrl-sidebar__preset-wrapper">
              <button
                className="ctrl-sidebar__preset-btn"
                onClick={() => setShowPresetMenu(o => !o)}
              >
                <FontAwesomeIcon icon={faFloppyDisk} />
                Presets
                <FontAwesomeIcon icon={faChevronDown} className="ctrl-sidebar__chevron" />
              </button>

              {showPresetMenu && (
                <div className="ctrl-sidebar__preset-menu">
                  {groupNames.length === 0 ? (
                    <div className="ctrl-sidebar__preset-empty">No saved presets</div>
                  ) : (
                    groupNames.map(groupName => (
                      <div key={groupName}>
                        <div className="ctrl-sidebar__preset-group-label">{groupName}</div>
                        {grouped[groupName].map(preset => (
                          <div key={preset.id} className="ctrl-sidebar__preset-item">
                            <button
                              className={`ctrl-sidebar__preset-star ${preset.isDefault ? 'ctrl-sidebar__preset-star--active' : ''}`}
                              onClick={() => onSetDefault(preset.id)}
                            >
                              <FontAwesomeIcon icon={preset.isDefault ? faSolidStar : faRegularStar} />
                            </button>
                            <span
                              className="ctrl-sidebar__preset-name"
                              onClick={() => { onLoadPreset(preset); setShowPresetMenu(false); }}
                            >
                              {preset.name}
                              {preset.isDefault && <span className="ctrl-sidebar__preset-badge">default</span>}
                            </span>
                            <button
                              className="ctrl-sidebar__preset-delete"
                              onClick={() => onDeletePreset(preset.id)}
                            >
                              <FontAwesomeIcon icon={faTrash} />
                            </button>
                          </div>
                        ))}
                      </div>
                    ))
                  )}
                  <div className="ctrl-sidebar__preset-divider" />
                  <div
                    className="ctrl-sidebar__preset-save-action"
                    onClick={() => { setShowPresetMenu(false); setShowSaveModal(true); }}
                  >
                    <FontAwesomeIcon icon={faFloppyDisk} />
                    Save current as preset...
                  </div>
                </div>
              )}
            </div>

            <button className="ctrl-sidebar__apply-btn" onClick={onApply}>
              <FontAwesomeIcon icon={faPlay} />
              Apply
            </button>

          </div>
        )}
      </aside>

      {showSaveModal && (
        <PresetSaveModal
          onSave={handleSave}
          onCancel={() => setShowSaveModal(false)}
        />
      )}
    </>
  );
};

export default ControlSidebar;
