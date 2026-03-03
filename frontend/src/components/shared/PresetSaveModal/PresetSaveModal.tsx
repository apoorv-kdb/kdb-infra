import { useState } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faXmark } from '@fortawesome/free-solid-svg-icons';
import './PresetSaveModal.scss';

interface PresetSaveModalProps {
  onSave:   (name: string, group: string) => void;
  onCancel: () => void;
  // Groups come from the server — passed in so the modal is data-driven
  groups?: string[];
}

const DEFAULT_GROUPS = ['My Presets', 'Shared'];

const PresetSaveModal = ({ onSave, onCancel, groups = DEFAULT_GROUPS }: PresetSaveModalProps) => {
  const [name,  setName]  = useState('');
  const [group, setGroup] = useState(groups[0] ?? 'My Presets');

  const handleSave = () => {
    if (name.trim()) onSave(name.trim(), group);
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
          <label className="preset-modal__label">Name</label>
          <input
            className="preset-modal__input"
            type="text"
            placeholder="e.g. EMEA Q1 View"
            value={name}
            onChange={e => setName(e.target.value)}
            onKeyDown={handleKeyDown}
            autoFocus
          />

          <label className="preset-modal__label" style={{ marginTop: 12 }}>Group</label>
          <select
            className="preset-modal__select preset-modal__select--full"
            value={group}
            onChange={e => setGroup(e.target.value)}
          >
            {groups.map(g => <option key={g} value={g}>{g}</option>)}
          </select>
        </div>

        <div className="preset-modal__footer">
          <button className="preset-modal__btn preset-modal__btn--cancel" onClick={onCancel}>
            Cancel
          </button>
          <button
            className="preset-modal__btn preset-modal__btn--save"
            onClick={handleSave}
            disabled={!name.trim()}
          >
            Save
          </button>
        </div>
      </div>
    </div>
  );
};

export default PresetSaveModal;
