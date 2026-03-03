import { useState, useRef, useEffect } from 'react';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faChevronDown, faXmark } from '@fortawesome/free-solid-svg-icons';
import './MultiSelectDropdown.scss';

interface Option {
  label: string;
  value: string;
}

interface MultiSelectDropdownProps {
  label:    string;
  options:  Option[];
  selected: string[];
  onChange: (selected: string[]) => void;
}

const MultiSelectDropdown = ({ label, options, selected, onChange }: MultiSelectDropdownProps) => {
  const [open, setOpen]   = useState(false);
  const containerRef      = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const toggle = (value: string) => {
    if (selected.includes(value)) {
      onChange(selected.filter(v => v !== value));
    } else {
      onChange([...selected, value]);
    }
  };

  const remove = (value: string, e: React.MouseEvent) => {
    e.stopPropagation();
    onChange(selected.filter(v => v !== value));
  };

  const labelFor = (value: string) =>
    options.find(o => o.value === value)?.label ?? value;

  return (
    <div className="ms-dropdown" ref={containerRef}>
      <label className="ms-dropdown__label">{label}</label>

      <div
        className={`ms-dropdown__trigger ${open ? 'ms-dropdown__trigger--open' : ''}`}
        onClick={() => setOpen(o => !o)}
      >
        <div className="ms-dropdown__chips">
          {selected.length === 0 ? (
            <span className="ms-dropdown__placeholder">None</span>
          ) : (
            selected.map(val => (
              <span key={val} className="ms-dropdown__chip">
                {labelFor(val)}
                <button className="ms-dropdown__chip-remove" onClick={e => remove(val, e)}>
                  <FontAwesomeIcon icon={faXmark} />
                </button>
              </span>
            ))
          )}
        </div>
        <FontAwesomeIcon
          icon={faChevronDown}
          className={`ms-dropdown__chevron ${open ? 'ms-dropdown__chevron--open' : ''}`}
        />
      </div>

      {open && (
        <div className="ms-dropdown__panel">
          {options.map(opt => (
            <div
              key={opt.value}
              className={`ms-dropdown__option ${selected.includes(opt.value) ? 'ms-dropdown__option--selected' : ''}`}
              onClick={() => toggle(opt.value)}
            >
              <span className="ms-dropdown__option-label">{opt.label}</span>
              {selected.includes(opt.value) && (
                <FontAwesomeIcon icon={faXmark} className="ms-dropdown__option-check" />
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default MultiSelectDropdown;
