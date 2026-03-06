import { useState, useEffect, useRef, useCallback } from 'react';
import { BaseImmediateState, CatalogField, FieldConfig, KVOption, Preset, QueryParams } from '../types';
import { parseFromUrl, pushUrlState } from '../services/urlSerializer';

// =============================================
// useDashboardState
// Core shared hook — every page uses this.
// All state logic lives here; page components are composition only.
// =============================================

export interface InitData<TDeferred> {
  latestAsofDate:  string;
  defaultPrevDate: string;
  catalogFields:   CatalogField[];
  filterOptions:   KVOption[];
  presets:         Preset<TDeferred>[];
}

interface Options<TImmediate extends BaseImmediateState, TDeferred> {
  fetchInitData:    () => Promise<InitData<TDeferred>>;
  savePresetFn:     (state: TDeferred, name: string, group: string) => Promise<Preset<TDeferred>>;
  deletePresetFn:   (id: string) => Promise<void>;
  setDefaultFn:     (id: string) => Promise<void>;
  defaultImmediate: TImmediate;
  defaultDeferred:  TDeferred;
  urlSync:          boolean;
  buildQueryParams: (immediate: TImmediate, deferred: TDeferred) => QueryParams;
}

interface UseDashboardStateReturn<TImmediate extends BaseImmediateState, TDeferred> {
  // Server data
  catalogFields:  CatalogField[];
  filterOptions:  KVOption[];
  presets:        Preset<TDeferred>[];
  loading:        boolean;
  error:          string | null;

  // State
  immediate:      TImmediate;
  draft:          TDeferred;
  appliedParams:  QueryParams | null;

  // Preset tracking
  activePresetId: string | null;
  isDirty:        boolean;

  // Actions
  setImmediate:      (patch: Partial<TImmediate>) => void;
  setDraft:          (patch: Partial<TDeferred>) => void;
  handleApply:       () => void;
  loadPreset:        (preset: Preset<TDeferred>) => void;
  revertPreset:      () => void;
  savePreset:        (name: string, group: string) => Promise<void>;
  deletePreset:      (id: string) => Promise<void>;
  setDefaultPreset:  (id: string) => Promise<void>;
}

const isDraftDirty = (a: unknown, b: unknown): boolean =>
  JSON.stringify(a) !== JSON.stringify(b);

export function useDashboardState<TImmediate extends BaseImmediateState, TDeferred>(
  options: Options<TImmediate, TDeferred>
): UseDashboardStateReturn<TImmediate, TDeferred> {
  const {
    fetchInitData, savePresetFn, deletePresetFn, setDefaultFn,
    defaultImmediate, defaultDeferred,
    urlSync, buildQueryParams,
  } = options;

  // Keep buildQueryParams in a ref so applyState never needs it as a dep.
  // This makes applyState — and everything that depends on it — truly stable,
  // eliminating the stale-closure cascade caused by the function recreating on
  // every SalesView render.
  const buildQueryParamsRef = useRef(buildQueryParams);
  buildQueryParamsRef.current = buildQueryParams;

  // ── Server data ──────────────────────────────────────────────────────────
  const [catalogFields,  setCatalogFields]  = useState<CatalogField[]>([]);
  const [filterOptions,  setFilterOptions]  = useState<KVOption[]>([]);
  const [presets,        setPresets]        = useState<Preset<TDeferred>[]>([]);
  const [loading,        setLoading]        = useState(true);
  const [error,          setError]          = useState<string | null>(null);

  // ── Refs for current state (avoid stale closures) ────────────────────────
  const immediateRef = useRef<TImmediate>(defaultImmediate);
  const draftRef     = useRef<TDeferred>(defaultDeferred);

  const [immediate,      setImmediateState] = useState<TImmediate>(defaultImmediate);
  const [draft,          setDraftState]     = useState<TDeferred>(defaultDeferred);
  const [appliedParams,  setAppliedParams]  = useState<QueryParams | null>(null);

  // ── Preset tracking ───────────────────────────────────────────────────────
  const [activePresetId, setActivePresetId] = useState<string | null>(null);
  const snapshotRef = useRef<TDeferred | null>(null);

  const isDirty = snapshotRef.current !== null
    ? isDraftDirty(draft, snapshotRef.current)
    : false;

  // ── Internal apply helper ─────────────────────────────────────────────────
  const applyState = useCallback((imm: TImmediate, def: TDeferred) => {
    const params = buildQueryParamsRef.current(imm, def);
    setAppliedParams(params);
    if (urlSync) pushUrlState(params);
  // urlSync is a primitive bool — safe dep. buildQueryParams via ref, no dep needed.
  }, [urlSync]); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Init ──────────────────────────────────────────────────────────────────
  useEffect(() => {
    fetchInitData()
      .then(data => {
        setCatalogFields(data.catalogFields);
        setFilterOptions(data.filterOptions);
        setPresets(data.presets);

        // Check URL first
        const urlParams = urlSync ? parseFromUrl(window.location.search) : {};
        const hasUrlState = Object.keys(urlParams).length > 0 && urlParams.asofDate;

        if (hasUrlState) {
          const newImmediate: TImmediate = {
            ...defaultImmediate,
            ...(urlParams.asofDate    && { asofDate:    urlParams.asofDate }),
            ...(urlParams.prevDate    && { prevDate:    urlParams.prevDate }),
            ...(urlParams.mode        && { mode:        urlParams.mode }),
            ...(urlParams.chartWindow && { chartWindow: urlParams.chartWindow }),
          };
          const newDraft: TDeferred = {
            ...defaultDeferred,
            ...(urlParams.measure      && { measure:      urlParams.measure }),
            ...(urlParams.fieldConfigs && { fieldConfigs: urlParams.fieldConfigs }),
            ...(urlParams.filters      && { filters:      kvRecordToArray(urlParams.filters) }),
            ...(urlParams.exclusions   && { exclusions:   kvRecordToArray(urlParams.exclusions) }),
          };
          setImmediateState(newImmediate);
          immediateRef.current = newImmediate;
          setDraftState(newDraft);
          draftRef.current = newDraft;
          applyState(newImmediate, newDraft);
        } else {
          const defaultPreset = data.presets.find(p => p.isDefault) ?? data.presets[0] ?? null;
          const newImmediate: TImmediate = {
            ...defaultImmediate,
            asofDate: data.latestAsofDate,
            prevDate: data.defaultPrevDate,
          } as TImmediate;

          if (defaultPreset) {
            setImmediateState(newImmediate);
            immediateRef.current = newImmediate;
            setDraftState(defaultPreset.state);
            draftRef.current = defaultPreset.state;
            snapshotRef.current = defaultPreset.state;
            setActivePresetId(defaultPreset.id);
            applyState(newImmediate, defaultPreset.state);
          } else {
            setImmediateState(newImmediate);
            immediateRef.current = newImmediate;
            applyState(newImmediate, defaultDeferred);
          }
        }
      })
      .catch(err => setError(String(err)))
      .finally(() => setLoading(false));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── setImmediate — fires immediately, updates appliedParams ───────────────
  const setImmediate = useCallback((patch: Partial<TImmediate>) => {
    setImmediateState(prev => {
      const next = { ...prev, ...patch };
      immediateRef.current = next;
      applyState(next, draftRef.current);
      return next;
    });
  }, [applyState]);

  // ── setDraft — stages changes, no immediate effect ────────────────────────
  const setDraft = useCallback((patch: Partial<TDeferred>) => {
    setDraftState(prev => {
      const next = { ...prev, ...patch };
      draftRef.current = next;
      return next;
    });
  }, []);

  // ── handleApply — flushes draft to appliedParams ──────────────────────────
  const handleApply = useCallback(() => {
    applyState(immediateRef.current, draftRef.current);
  }, [applyState]);

  // ── loadPreset ────────────────────────────────────────────────────────────
  const loadPreset = useCallback((preset: Preset<TDeferred>) => {
    setDraftState(preset.state);
    draftRef.current = preset.state;
    snapshotRef.current = preset.state;
    setActivePresetId(preset.id);
    applyState(immediateRef.current, preset.state);
  }, [applyState]);

  // ── revertPreset ──────────────────────────────────────────────────────────
  const revertPreset = useCallback(() => {
    if (!snapshotRef.current) return;
    const snap = snapshotRef.current;
    setDraftState(snap);
    draftRef.current = snap;
    applyState(immediateRef.current, snap);
  }, [applyState]);

  // ── savePreset ────────────────────────────────────────────────────────────
  const savePreset = useCallback(async (name: string, group: string) => {
    let currentDraft: TDeferred = defaultDeferred;
    setDraftState(d => { currentDraft = d; return d; });
    await new Promise(r => setTimeout(r, 0));
    const saved = await savePresetFn(currentDraft, name, group);
    setPresets(prev => [...prev, saved]);
    snapshotRef.current = saved.state;
    setActivePresetId(saved.id);
  }, [savePresetFn, defaultDeferred]);

  // ── deletePreset ──────────────────────────────────────────────────────────
  const deletePreset = useCallback(async (id: string) => {
    await deletePresetFn(id);
    setPresets(prev => prev.filter(p => p.id !== id));
    if (activePresetId === id) {
      setActivePresetId(null);
      snapshotRef.current = null;
    }
  }, [deletePresetFn, activePresetId]);

  // ── setDefaultPreset ──────────────────────────────────────────────────────
  const setDefaultPreset = useCallback(async (id: string) => {
    await setDefaultFn(id);
    setPresets(prev => prev.map(p => ({ ...p, isDefault: p.id === id })));
  }, [setDefaultFn]);

  return {
    catalogFields, filterOptions, presets, loading, error,
    immediate, draft, appliedParams,
    activePresetId, isDirty,
    setImmediate, setDraft, handleApply,
    loadPreset, revertPreset, savePreset, deletePreset, setDefaultPreset,
  };
}

// Helper: convert Record<string, string[]> to KVOption[]
const kvRecordToArray = (rec: Record<string, string[]>): KVOption[] =>
  Object.entries(rec).flatMap(([key, values]) => values.map(value => ({ key, value })));
