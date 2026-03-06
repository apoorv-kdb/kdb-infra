import { useState } from 'react';
import { useDashboardState } from '../../hooks/useDashboardState';
import { SalesImmediateState, SalesDraftState, DEFAULT_SALES_IMMEDIATE, DEFAULT_SALES_DRAFT } from '../../types/sales';
import { QueryParams, KVOption, FieldConfig } from '../../types';
import AppShell from '../../components/AppShell/AppShell';
import ControlSidebar from '../../components/ControlSidebar/ControlSidebar';
import PresetBar from '../../components/PresetBar/PresetBar';
import AppliedParamsBar from '../../components/AppliedParamsBar/AppliedParamsBar';
import Dashboard from '../../components/Dashboard/Dashboard';
import KVDropdown from '../../components/shared/KVDropdown';
import FieldPicker from '../../components/FieldPicker/FieldPicker';
import {
  getInitData, getRegionSummaryFlat, getSpotData, getTrendByDimension,
  savePreset, deletePreset, setDefaultPreset,
  // TO CONNECT REAL BACKEND: swap the line above for:
  // } from './salesService';
} from './mockService';
import './SalesView.scss';

const SIDEBAR_KEY = 'kdb-sidebar-collapsed';

// Build QueryParams from immediate + draft state
const buildQueryParams = (imm: SalesImmediateState, draft: SalesDraftState): QueryParams => {
  const collapse = (pairs: KVOption[]): Record<string, string[]> =>
    pairs.reduce((acc, { key, value }) => {
      acc[key] = [...(acc[key] ?? []), value];
      return acc;
    }, {} as Record<string, string[]>);

  return {
    asofDate:    imm.asofDate,
    prevDate:    imm.prevDate,
    mode:        imm.mode,
    chartWindow: imm.chartWindow,
    measure:     draft.measure,
    fieldConfigs: draft.fieldConfigs,
    filters:     collapse(draft.filters),
    exclusions:  collapse(draft.exclusions),
  };
};

const SalesView = () => {
  const [collapsed, setCollapsed] = useState<boolean>(() =>
    localStorage.getItem(SIDEBAR_KEY) === 'true'
  );

  const toggleCollapse = () => {
    setCollapsed(prev => {
      localStorage.setItem(SIDEBAR_KEY, String(!prev));
      return !prev;
    });
  };

  const {
    catalogFields, filterOptions, presets,
    immediate, draft, appliedParams,
    activePresetId, isDirty,
    setImmediate, setDraft,
    handleApply, loadPreset, revertPreset,
    savePreset: handleSavePreset,
    deletePreset: handleDeletePreset,
    setDefaultPreset: handleSetDefault,
  } = useDashboardState<SalesImmediateState, SalesDraftState>({
    fetchInitData:    getInitData,
    savePresetFn:     savePreset,
    deletePresetFn:   deletePreset,
    setDefaultFn:     setDefaultPreset,
    defaultImmediate: DEFAULT_SALES_IMMEDIATE,
    defaultDeferred:  DEFAULT_SALES_DRAFT,
    urlSync:          true,
    buildQueryParams,
  });

  const header = (
    <header className="app-header">
      <div className="app-header__left">
        <span className="app-header__logo">KDB Analytics</span>
        <span className="app-header__sep">|</span>
        <span className="app-header__sub">Sales Dashboard</span>
      </div>
      <div className="app-header__right">
        <span className="app-header__env-badge">MOCK</span>
      </div>
    </header>
  );

  const commandZone = (
    <>
      <PresetBar
        presets={presets}
        activePresetId={activePresetId}
        isDirty={isDirty}
        onLoadPreset={p => loadPreset(p as never)}
        onRevertPreset={revertPreset}
        onSavePreset={handleSavePreset}
      />
      {appliedParams && (
        <AppliedParamsBar params={appliedParams} catalogFields={catalogFields} />
      )}
    </>
  );

  const sidebar = (
    <ControlSidebar
      asofDate={immediate.asofDate}
      prevDate={immediate.prevDate}
      onAsofChange={v => setImmediate({ asofDate: v })}
      onPrevChange={v => setImmediate({ prevDate: v })}
      mode={immediate.mode}
      onModeChange={v => setImmediate({ mode: v })}
      chartWindow={immediate.chartWindow}
      onChartWindowChange={v => setImmediate({ chartWindow: v as SalesImmediateState['chartWindow'] })}
      onApply={handleApply}
      collapsed={collapsed}
      onToggleCollapse={toggleCollapse}
    >
      {/* Sales-specific deferred controls */}
      <div className="sales-sidebar__section">
        <div className="sales-sidebar__label">Filters</div>
        <KVDropdown
          label=""
          options={filterOptions}
          selected={draft.filters}
          onChange={v => setDraft({ filters: v })}
          loading={false}
        />
      </div>
      <div className="sales-sidebar__section">
        <div className="sales-sidebar__label">Exclusions</div>
        <KVDropdown
          label=""
          options={filterOptions}
          selected={draft.exclusions}
          onChange={v => setDraft({ exclusions: v })}
          loading={false}
        />
      </div>
      <div className="sales-sidebar__section sales-sidebar__section--fields">
        <div className="sales-sidebar__label">Fields</div>
        <FieldPicker
          fields={catalogFields}
          measure={draft.measure}
          fieldConfigs={draft.fieldConfigs}
          onMeasureChange={v => setDraft({ measure: v })}
          onFieldConfigsChange={(v: FieldConfig[]) => setDraft({ fieldConfigs: v })}
        />
      </div>
    </ControlSidebar>
  );

  return (
    <AppShell
      header={header}
      commandZone={commandZone}
      sidebar={sidebar}
    >
      {appliedParams ? (
        <Dashboard
          params={appliedParams}
          catalogFields={catalogFields}
          getRegionSummaryFlat={(p, field) => getRegionSummaryFlat(p, field)}
          getSpotData={(p, field) => getSpotData(p, field)}
          getTrendByDimension={(p, field) => getTrendByDimension(p, field)}
        />
      ) : (
        <div className="sales-view__loading">Initializing…</div>
      )}
    </AppShell>
  );
};

export default SalesView;
