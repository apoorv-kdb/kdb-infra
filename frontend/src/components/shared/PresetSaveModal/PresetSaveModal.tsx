import { useState } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faXmark } from '@fortawesome/free-solid-svg-icons';
import './PresetSaveModal.scss';

interface PresetSaveModalProps {
  onSave:   (name: string, group: string) => void;
  onCancel: () => void;
}

const COMMON_GROUPS = ['Personal', 'EMEA', 'APAC', 'AMER', 'Global'];

const PresetSaveModal = ({ onSave, onCancel }: PresetSaveModalProps) => {
  const [name,  setName]  = useState('');
  const [group, setGroup] = useState('Personal');
  const [customGroup, setCustomGroup] = useState('');
  const [useCustom, setUseCustom] = useState(false);

  const effectiveGroup = useCustom ? customGroup : group;

  const handleSave = () => {
    if (name.trim() && effectiveGroup.trim()) {
      onSave(name.trim(), effectiveGroup.trim());
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter')  handleSave();
    if (e.key === 'Escape') onCancel();
  };

  return (
    <div className="preset-modal__backdrop" onClick={onCancel}>
      <div className="preset-modal" onClick={e => e.stopPropagation()}>
        <div className="preset-modal__header">
          <span className="preset-modal__title">Save Preset</span>
          <button className="preset-modal__close" onClick={onCancel}>
            <FontAwesomeIcon icon={faXmark} />
          </button>
        </div>

        <div className="preset-modal__body">
          <label className="preset-modal__label">Preset name</label>
          <input
            className="preset-modal__input"
            type="text"
            placeholder="e.g. EMEA Computers Q1"
            value={name}
            onChange={e => setName(e.target.value)}
            onKeyDown={handleKeyDown}
            autoFocus
          />

          <label className="preset-modal__label" style={{ marginTop: 12 }}>Group</label>
          {!useCustom ? (
            <div className="preset-modal__group-row">
              <select
                className="preset-modal__select"
                value={group}
                onChange={e => setGroup(e.target.value)}
              >
                {COMMON_GROUPS.map(g => (
                  <option key={g} value={g}>{g}</option>
                ))}
              </select>
              <button
                className="preset-modal__link"
                onClick={() => setUseCustom(true)}
              >
                Custom...
              </button>
            </div>
          ) : (
            <div className="preset-modal__group-row">
              <input
                className="preset-modal__input"
                type="text"
                placeholder="Enter group name"
                value={customGroup}
                onChange={e => setCustomGroup(e.target.value)}
                onKeyDown={handleKeyDown}
              />
              <button
                className="preset-modal__link"
                onClick={() => { setUseCustom(false); setCustomGroup(''); }}
              >
                Cancel
              </button>
            </div>
          )}
        </div>

        <div className="preset-modal__footer">
          <button className="preset-modal__btn preset-modal__btn--cancel" onClick={onCancel}>
            Cancel
          </button>
          <button
            className="preset-modal__btn preset-modal__btn--save"
            onClick={handleSave}
            disabled={!name.trim() || !effectiveGroup.trim()}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
};

export default PresetSaveModal;
