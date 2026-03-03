// Legacy hook — superseded by useDashboardState
// Kept to avoid dead-file TS errors during transition
export const groupPresets = <T>(presets: { group?: string; id: string; state: T }[]): Record<string, typeof presets> =>
  presets.reduce((acc, p) => {
    const g = p.group ?? 'Personal';
    acc[g] = [...(acc[g] ?? []), p];
    return acc;
  }, {} as Record<string, typeof presets>);
