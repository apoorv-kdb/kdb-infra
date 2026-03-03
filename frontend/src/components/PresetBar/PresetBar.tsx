import { useState, useEffect, useRef } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faChevronDown, faPlus, faRotateLeft } from '@fortawesome/free-solid-svg-icons';
import { Preset } from '../../types';
import PresetSaveModal from '../shared/PresetSaveModal/PresetSaveModal';
import './PresetBar.scss';

const VISIBLE_COUNT = 10;

interface PresetBarProps {
  presets:        Preset<unknown>[];
  activePresetId: string | null;
  isDirty:        boolean;
  onLoadPreset:   (preset: Preset<unknown>) => void;
  onRevertPreset: () => void;
  onSavePreset:   (name: string, group: string) => void;
}

const PresetBar = ({
  presets, activePresetId, isDirty,
  onLoadPreset, onRevertPreset, onSavePreset,
}: PresetBarProps) => {
  const [showMore,      setShowMore]      = useState(false);
  const [showSaveModal, setShowSaveModal] = useState(false);
  const moreRef = useRef<HTMLDivElement>(null);

  // Close More dropdown on click outside
  useEffect(() => {
    if (!showMore) return;
    const handler = (e: MouseEvent) => {
      if (moreRef.current && !moreRef.current.contains(e.target as Node)) {
        setShowMore(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [showMore]);

  const visible  = presets.slice(0, VISIBLE_COUNT);
  const overflow = presets.slice(VISIBLE_COUNT);

  // Group overflow presets
  const overflowGroups = overflow.reduce((acc, p) => {
    const g = p.group ?? 'Other';
    acc[g] = [...(acc[g] ?? []), p];
    return acc;
  }, {} as Record<string, Preset<unknown>[]>);

  const handleLoad = (preset: Preset<unknown>) => {
    onLoadPreset(preset);
    setShowMore(false);
  };

  const handleSave = (name: string, group: string) => {
    onSavePreset(name, group);
    setShowSaveModal(false);
  };

  // Build grouped visible chips
  const visibleGroups: { group: string; presets: Preset<unknown>[] }[] = [];
  const seen: Record<string, boolean> = {};
  visible.forEach(p => {
    const g = p.group ?? 'Other';
    if (!seen[g]) {
      seen[g] = true;
      visibleGroups.push({ group: g, presets: [] });
    }
    visibleGroups[visibleGroups.length - 1].presets.push(p);
  });

  return (
    <>
      <div className="preset-bar">
        <div className="preset-bar__chips">
          {visibleGroups.map(({ group, presets: gPresets }, gi) => (
            <div key={group} className="preset-bar__group">
              {gi > 0 && <div className="preset-bar__group-divider" />}
              <span className="preset-bar__group-label">{group}</span>
              {gPresets.map(preset => {
                const isActive = preset.id === activePresetId;
                const showDirty = isActive && isDirty;
                return (
                  <button
                    key={preset.id}
                    className={`preset-bar__chip ${isActive ? 'preset-bar__chip--active' : ''} ${showDirty ? 'preset-bar__chip--dirty' : ''}`}
                    onClick={() => handleLoad(preset)}
                  >
                    {preset.name}
                    {showDirty && (
                      <>
                        <span className="preset-bar__dirty-dot">●</span>
                        <span
                          className="preset-bar__revert"
                          title="Revert to saved"
                          onClick={e => { e.stopPropagation(); onRevertPreset(); }}
                        >
                          <FontAwesomeIcon icon={faRotateLeft} />
                        </span>
                      </>
                    )}
                  </button>
                );
              })}
            </div>
          ))}

          {/* Overflow dropdown */}
          {overflow.length > 0 && (
            <div className="preset-bar__more-wrapper" ref={moreRef}>
              <button
                className="preset-bar__more-btn"
                onClick={() => setShowMore(o => !o)}
              >
                More <FontAwesomeIcon icon={faChevronDown} />
              </button>
              {showMore && (
                <div className="preset-bar__more-menu">
                  {Object.entries(overflowGroups).map(([group, gPresets]) => (
                    <div key={group}>
                      <div className="preset-bar__more-group-label">{group}</div>
                      {gPresets.map(preset => (
                        <button
                          key={preset.id}
                          className={`preset-bar__more-item ${preset.id === activePresetId ? 'preset-bar__more-item--active' : ''}`}
                          onClick={() => handleLoad(preset)}
                        >
                          {preset.name}
                          {preset.id === activePresetId && isDirty && (
                            <span className="preset-bar__dirty-dot">●</span>
                          )}
                        </button>
                      ))}
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}
        </div>

        <button
          className="preset-bar__save-btn"
          onClick={() => setShowSaveModal(true)}
          title="Save current as preset"
        >
          <FontAwesomeIcon icon={faPlus} />
        </button>
      </div>

      {showSaveModal && (
        <PresetSaveModal
          onSave={handleSave}
          onCancel={() => setShowSaveModal(false)}
        />
      )}
    </>
  );
};

export default PresetBar;
