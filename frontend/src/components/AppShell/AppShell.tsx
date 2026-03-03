import './AppShell.scss';

interface AppShellProps {
  header:      React.ReactNode;
  commandZone: React.ReactNode;
  sidebar:     React.ReactNode;
  children:    React.ReactNode;
}

const AppShell = ({ header, commandZone, sidebar, children }: AppShellProps) => (
  <div className="app-shell">
    <div className="app-shell__header">{header}</div>
    <div className="app-shell__command-zone">{commandZone}</div>
    <div className="app-shell__body">
      {sidebar}
      <div className="app-shell__main">
        <div className="app-shell__dashboard">{children}</div>
      </div>
    </div>
  </div>
);

export default AppShell;
