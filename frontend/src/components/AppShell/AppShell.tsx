import './AppShell.scss';

interface AppShellProps {
  header:    React.ReactNode;
  sidebar:   React.ReactNode;
  paramsBar: React.ReactNode | null;
  children:  React.ReactNode;
}

const AppShell = ({ header, sidebar, paramsBar, children }: AppShellProps) => (
  <div className="app-shell">
    <div className="app-shell__header">{header}</div>
    <div className="app-shell__body">
      {sidebar}
      <div className="app-shell__main">
        {paramsBar && <div className="app-shell__params-bar">{paramsBar}</div>}
        <div className="app-shell__dashboard">{children}</div>
      </div>
    </div>
  </div>
);

export default AppShell;
