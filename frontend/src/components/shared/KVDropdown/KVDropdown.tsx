import { useState, useRef, useEffect, useCallback } from 'react';
import ReactDOM from 'react-dom';
import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faChevronDown, faXmark, faSearch } from '@fortawesome/free-solid-svg-icons';
import { KVOption } from '../../../types';
import './KVDropdown.scss';

interface KVDropdownProps {
  label:    string;
  options:  KVOption[];
  selected: KVOption[];
  onChange: (selected: KVOption[]) => void;
  loading?: boolean;
}

const kvEqual = (a: KVOption, b: KVOption) =>
  a.key === b.key && a.value === b.value;

const KVDropdown = ({ label, options, selected, onChange, loading }: KVDropdownProps) => {
  const [open,   setOpen]   = useState(false);
  const [search, setSearch] = useState('');
  const triggerRef = useRef<HTMLDivElement>(null);
  const panelRef   = useRef<HTMLDivElement>(null);

  // Portal panel position — recalculate on open
  const [panelStyle, setPanelStyle] = useState<React.CSSProperties>({});

  const computePanelPosition = () => {
    if (!triggerRef.current) return;
    const rect = triggerRef.current.getBoundingClientRect();
    setPanelStyle({
      position: 'fixed',
      top:      rect.bottom + 4,
      left:     rect.left,
      width:    Math.max(rect.width, 280),
      zIndex:   9999,
    });
  };

  useEffect(() => {
    if (open) computePanelPosition();
  }, [open]);

  // Close on outside click
  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      const target = e.target as Node;
      if (
        triggerRef.current?.contains(target) ||
        panelRef.current?.contains(target)
      ) return;
      setOpen(false);
      setSearch('');
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  // Close on scroll/resize to keep position accurate
  useEffect(() => {
    if (!open) return;
    const handleScrollResize = () => { setOpen(false); };
    window.addEventListener('scroll', handleScrollResize, true);
    window.addEventListener('resize', handleScrollResize);
    return () => {
      window.removeEventListener('scroll', handleScrollResize, true);
      window.removeEventListener('resize', handleScrollResize);
    };
  }, [open]);

  const filtered = options.filter(opt => {
    const term = search.toLowerCase();
    return opt.key.toLowerCase().includes(term) || opt.value.toLowerCase().includes(term);
  });

  const isSelected = useCallback(
    (opt: KVOption) => selected.some(s => kvEqual(s, opt)),
    [selected]
  );

  const toggle = (opt: KVOption) => {
    if (isSelected(opt)) onChange(selected.filter(s => !kvEqual(s, opt)));
    else                 onChange([...selected, opt]);
  };

  const remove = (opt: KVOption, e: React.MouseEvent) => {
    e.stopPropagation();
    onChange(selected.filter(s => !kvEqual(s, opt)));
  };

  // Panel rendered via portal — escapes any overflow container
  const panel = open ? ReactDOM.createPortal(
    <div className="kv-dropdown__panel" style={panelStyle} ref={panelRef}>
      <div className="kv-dropdown__search">
        <FontAwesomeIcon icon={faSearch} className="kv-dropdown__search-icon" />
        <input
          className="kv-dropdown__search-input"
          placeholder="Search key or value..."
          value={search}
          onChange={e => setSearch(e.target.value)}
          autoFocus
        />
      </div>
      <div className="kv-dropdown__list">
        {loading ? (
          <div className="kv-dropdown__empty">Loading...</div>
        ) : filtered.length === 0 ? (
          <div className="kv-dropdown__empty">No results</div>
        ) : (
          filtered.map(opt => (
            <div
              key={`${opt.key}:${opt.value}`}
              className={`kv-dropdown__option ${isSelected(opt) ? 'kv-dropdown__option--selected' : ''}`}
              onClick={() => toggle(opt)}
            >
              <span className="kv-dropdown__option-key">{opt.key}</span>
              <span className="kv-dropdown__option-arrow">→</span>
              <span className="kv-dropdown__option-value">{opt.value}</span>
              {isSelected(opt) && (
                <FontAwesomeIcon icon={faXmark} className="kv-dropdown__option-check" />
              )}
            </div>
          ))
        )}
      </div>
    </div>,
    document.body
  ) : null;

  return (
    <div className="kv-dropdown">
      {label && <label className="kv-dropdown__label">{label}</label>}

      <div
        ref={triggerRef}
        className={`kv-dropdown__trigger ${open ? 'kv-dropdown__trigger--open' : ''}`}
        onClick={() => setOpen(o => !o)}
      >
        <div className="kv-dropdown__chips">
          {selected.length === 0 ? (
            <span className="kv-dropdown__placeholder">All</span>
          ) : (
            selected.map(opt => (
              <span key={`${opt.key}:${opt.value}`} className="kv-dropdown__chip">
                <span className="kv-dropdown__chip-key">{opt.key}:</span>
                <span className="kv-dropdown__chip-value">{opt.value}</span>
                <button className="kv-dropdown__chip-remove" onClick={e => remove(opt, e)}>
                  <FontAwesomeIcon icon={faXmark} />
                </button>
              </span>
            ))
          )}
        </div>
        <FontAwesomeIcon
          icon={faChevronDown}
          className={`kv-dropdown__chevron ${open ? 'kv-dropdown__chevron--open' : ''}`}
        />
      </div>

      {panel}
    </div>
  );
};

export default KVDropdown;
