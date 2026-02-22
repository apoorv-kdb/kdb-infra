import { useState, useEffect } from 'react';
import {
  ControlBarState, DEFAULT_CONTROL_BAR_STATE,
  KVOption, QueryParams, toQueryParams, CatalogField,
} from '../../types';
import { usePresets } from '../../hooks/usePresets';
import AppShell from '../../components/AppShell/AppShell';
import ControlSidebar from '../../components/ControlSidebar/ControlSidebar';
import AppliedParamsBar from '../../components/AppliedParamsBar/AppliedParamsBar';
import Dashboard from '../../components/Dashboard/Dashboard';
import DatePicker from '../../components/shared/DatePicker/DatePicker';
import KVDropdown from '../../components/shared/KVDropdown/KVDropdown';
import SelectDropdown from '../../components/shared/SelectDropdown/SelectDropdown';
import {
  getCatalogFields, getFilterOptions,
  getRegionSummaryFlat, getTrendByDimension,
  WINDOW_OPTIONS,
} from './salesService';
import './SalesView.scss';

const SIDEBAR_KEY = 'kdb-sidebar-collapsed';

const SalesView = () => {
  const { presets, savePreset, deletePreset, setDefault, defaultPreset } = usePresets();

  // ── Catalog — fetched from KDB+ on mount ──────────────────────────────────
  const [catalogFields,   setCatalogFields]   = useState<CatalogField[]>([]);
  const [catalogLoading,  setCatalogLoading]  = useState(true);
  const [catalogError,    setCatalogError]    = useState<string | null>(null);

  useEffect(() => {
    getCatalogFields()
      .then(setCatalogFields)
      .catch(err => setCatalogError(String(err)))
      .finally(() => setCatalogLoading(false));
  }, []);

  // ── Filter options — fetched after catalog loads ───────────────────────────
  const [filterOptions,  setFilterOptions]  = useState<KVOption[]>([]);
  const [filterLoading,  setFilterLoading]  = useState(true);

  useEffect(() => {
    getFilterOptions()
      .then(setFilterOptions)
      .catch(err => console.error('Filter options failed:', err))
      .finally(() => setFilterLoading(false));
  }, []);

  // ── Control state ──────────────────────────────────────────────────────────
  const [draft, setDraft] = useState<ControlBarState>(
    defaultPreset ? defaultPreset.state : DEFAULT_CONTROL_BAR_STATE
  );

  const setField = <K extends keyof ControlBarState>(key: K, value: ControlBarState[K]) =>
    setDraft(prev => ({ ...prev, [key]: value }));

  const [appliedParams, setAppliedParams] = useState<QueryParams | null>(null);

  const [collapsed, setCollapsed] = useState<boolean>(() =>
    localStorage.getItem(SIDEBAR_KEY) === 'true'
  );

  const toggleCollapse = () => {
    setCollapsed(prev => {
      localStorage.setItem(SIDEBAR_KEY, String(!prev));
      return !prev;
    });
  };

  const handleApply = () => setAppliedParams(toQueryParams(draft));

  // ── Render ─────────────────────────────────────────────────────────────────
  const header = (
    <header className="app-header">
      <div className="app-header__left">
        <span className="app-header__logo">KDB Analytics</span>
        <span className="app-header__sep">|</span>
        <span className="app-header__sub">Sales Dashboard</span>
      </div>
      <div className="app-header__right">
        <span className="app-header__env-badge">DEV</span>
      </div>
    </header>
  );

  // Show a loading/error banner while catalog is initialising
  if (catalogLoading) {
    return (
      <AppShell header={header} sidebar={null} paramsBar={null}>
        <div className="sales-view__empty">Loading catalog from KDB+…</div>
      </AppShell>
    );
  }

  if (catalogError) {
    return (
      <AppShell header={header} sidebar={null} paramsBar={null}>
        <div className="sales-view__empty" style={{ color: '#C62828' }}>
          Failed to load catalog: {catalogError}
          <br /><small>Is the KDB+ server running on port 5010?</small>
        </div>
      </AppShell>
    );
  }

  const sidebar = (
    <ControlSidebar
      collapsed={collapsed}
      onToggleCollapse={toggleCollapse}
      draft={draft}
      onFieldChange={setField}
      onApply={handleApply}
      datePickerAsof={
        <DatePicker label="AsOf" value={draft.asofDate} onChange={v => setField('asofDate', v)} />
      }
      datePickerPrev={
        <DatePicker label="Prev" value={draft.prevDate} onChange={v => setField('prevDate', v)} />
      }
      windowSelector={
        <SelectDropdown
          label="Window"
          options={WINDOW_OPTIONS}
          value={draft.chartWindow}
          onChange={v => setField('chartWindow', v as ControlBarState['chartWindow'])}
        />
      }
      filterDropdown={
        <KVDropdown
          label=""
          options={filterOptions}
          selected={draft.filters}
          onChange={v => setField('filters', v)}
          loading={filterLoading}
        />
      }
      exclusionDropdown={
        <KVDropdown
          label=""
          options={filterOptions}
          selected={draft.exclusions}
          onChange={v => setField('exclusions', v)}
          loading={filterLoading}
        />
      }
      catalogFields={catalogFields}
      presets={presets}
      onSavePreset={savePreset}
      onLoadPreset={p => setDraft(p.state)}
      onDeletePreset={deletePreset}
      onSetDefault={setDefault}
    />
  );

  return (
    <AppShell
      header={header}
      sidebar={sidebar}
      paramsBar={
        appliedParams
          ? <AppliedParamsBar params={appliedParams} catalogFields={catalogFields} />
          : null
      }
    >
      {appliedParams ? (
        <Dashboard
          params={appliedParams}
          catalogFields={catalogFields}
          getRegionSummaryFlat={(p, field) => getRegionSummaryFlat(p, field)}
          getTransactions={() => Promise.resolve([])}
          getTrendByDimension={(p, field) => getTrendByDimension(p, field)}
        />
      ) : (
        <div className="sales-view__empty">
          Select fields in the sidebar and click Apply.
        </div>
      )}
    </AppShell>
  );
};

export default SalesView;
