import { FontAwesomeIcon } from '@fortawesome/react-fontawesome';
import { faPlay, faChevronLeft, faChevronRight } from '@fortawesome/free-solid-svg-icons';
import { AnalyticalMode } from '../../types';
import './ControlSidebar.scss';

// WINDOW_OPTIONS lives here — it's UI config for this component only
export const WINDOW_OPTIONS = [
  { label: '30 Days', value: '30d' },
  { label: '60 Days', value: '60d' },
  { label: '90 Days', value: '90d' },
  { label: '1 Year',  value: '1Y'  },
];

interface ControlSidebarProps {
  // Always present
  asofDate:         string | null;
  onAsofChange:     (v: string) => void;
  onApply:          () => void;
  collapsed:        boolean;
  onToggleCollapse: () => void;

  // Optional — WithComparison pages
  prevDate?:        string | null;
  onPrevChange?:    (v: string) => void;
  mode?:            AnalyticalMode;
  onModeChange?:    (v: AnalyticalMode) => void;

  // Optional — WithTrend pages
  chartWindow?:         string;
  onChartWindowChange?: (v: string) => void;

  // Page-specific controls
  children?: React.ReactNode;
}

const Section = ({ label, children }: { label: string; children: React.ReactNode }) => (
  <div className="ctrl-sidebar__section">
    <div className="ctrl-sidebar__section-label">{label}</div>
    <div className="ctrl-sidebar__section-body">{children}</div>
  </div>
);

const ControlSidebar = ({
  asofDate, onAsofChange,
  prevDate, onPrevChange,
  mode, onModeChange,
  chartWindow, onChartWindowChange,
  onApply,
  collapsed, onToggleCollapse,
  children,
}: ControlSidebarProps) => {
  const hasComparison = mode !== undefined && onModeChange !== undefined;
  const hasTrend      = chartWindow !== undefined && onChartWindowChange !== undefined;
  const hasPrev       = prevDate !== undefined && onPrevChange !== undefined;

  return (
    <aside className={`ctrl-sidebar ${collapsed ? 'ctrl-sidebar--collapsed' : ''}`}>
      <button className="ctrl-sidebar__toggle" onClick={onToggleCollapse}>
        <FontAwesomeIcon icon={collapsed ? faChevronRight : faChevronLeft} />
      </button>

      {!collapsed && (
        <div className="ctrl-sidebar__content">

          {/* Mode toggle — only if opted in */}
          {hasComparison && (
            <Section label="Mode">
              <div className="ctrl-sidebar__mode-toggle">
                <button
                  className={`ctrl-sidebar__mode-btn ${mode === 'movement' ? 'ctrl-sidebar__mode-btn--active' : ''}`}
                  onClick={() => onModeChange!('movement')}
                >
                  Movement
                </button>
                <button
                  className={`ctrl-sidebar__mode-btn ${mode === 'spot' ? 'ctrl-sidebar__mode-btn--active' : ''}`}
                  onClick={() => onModeChange!('spot')}
                >
                  Spot
                </button>
              </div>
            </Section>
          )}

          {/* Dates */}
          <Section label="Dates">
            <div className={`ctrl-sidebar__row ${hasPrev ? 'ctrl-sidebar__row--two' : 'ctrl-sidebar__row--one'}`}>
              <div className="ctrl-sidebar__date-field">
                <div className="ctrl-sidebar__date-label">ASOF</div>
                <input
                  type="date"
                  className="ctrl-sidebar__date-input"
                  value={asofDate ?? ''}
                  onChange={e => onAsofChange(e.target.value)}
                />
              </div>
              {hasPrev && (
                <div className="ctrl-sidebar__date-field">
                  <div className="ctrl-sidebar__date-label">PREV</div>
                  <input
                    type="date"
                    className="ctrl-sidebar__date-input"
                    value={prevDate ?? ''}
                    onChange={e => onPrevChange!(e.target.value)}
                  />
                </div>
              )}
            </div>
          </Section>

          {/* Page-specific controls */}
          {children && (
            <div className="ctrl-sidebar__page-controls">
              {children}
            </div>
          )}

          {/* Chart window — only if opted in */}
          {hasTrend && (
            <Section label="Window">
              <div className="ctrl-sidebar__window-options">
                {WINDOW_OPTIONS.map(opt => (
                  <button
                    key={opt.value}
                    className={`ctrl-sidebar__window-btn ${chartWindow === opt.value ? 'ctrl-sidebar__window-btn--active' : ''}`}
                    onClick={() => onChartWindowChange!(opt.value)}
                  >
                    {opt.label}
                  </button>
                ))}
              </div>
            </Section>
          )}

          <div className="ctrl-sidebar__spacer" />

          <button className="ctrl-sidebar__apply-btn" onClick={onApply}>
            <FontAwesomeIcon icon={faPlay} />
            Apply
          </button>

        </div>
      )}
    </aside>
  );
};

export default ControlSidebar;
