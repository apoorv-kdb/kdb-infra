import { useState, useCallback } from 'react';
import { Preset, ControlBarState } from '../types';

const STORAGE_KEY = 'kdb-analytics-presets';

const loadFromStorage = (): Preset[] => {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch { return []; }
};

const saveToStorage = (presets: Preset[]): void => {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(presets));
};

// Returns presets grouped by their group field
export const groupPresets = (presets: Preset[]): Record<string, Preset[]> =>
  presets.reduce((acc, p) => {
    const g = p.group ?? 'Personal';
    acc[g] = [...(acc[g] ?? []), p];
    return acc;
  }, {} as Record<string, Preset[]>);

interface UsePresetsReturn {
  presets:      Preset[];
  savePreset:   (name: string, group: string, state: ControlBarState) => void;
  deletePreset: (id: string) => void;
  setDefault:   (id: string) => void;
  defaultPreset: Preset | null;
}

export const usePresets = (): UsePresetsReturn => {
  const [presets, setPresets] = useState<Preset[]>(loadFromStorage);

  const defaultPreset = presets.find(p => p.isDefault) ?? null;

  const savePreset = useCallback((name: string, group: string, state: ControlBarState) => {
    const newPreset: Preset = {
      id: crypto.randomUUID(),
      name: name.trim(),
      group: group.trim() || 'Personal',
      isDefault: false,
      state,
      createdAt: new Date().toISOString(),
    };
    setPresets(prev => {
      const updated = [...prev, newPreset];
      saveToStorage(updated);
      return updated;
    });
  }, []);

  const deletePreset = useCallback((id: string) => {
    setPresets(prev => {
      const updated = prev.filter(p => p.id !== id);
      saveToStorage(updated);
      return updated;
    });
  }, []);

  // Toggle default — only one preset can be default at a time
  const setDefault = useCallback((id: string) => {
    setPresets(prev => {
      const updated = prev.map(p => ({
        ...p,
        isDefault: p.id === id ? !p.isDefault : false,
      }));
      saveToStorage(updated);
      return updated;
    });
  }, []);

  return { presets, savePreset, deletePreset, setDefault, defaultPreset };
};
