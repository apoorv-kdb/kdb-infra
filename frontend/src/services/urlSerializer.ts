import { QueryParams, FieldConfig, KVOption } from '../types';

// =============================================
// URL SERIALIZER
// Shared utility — not page-specific
// replaceState on every appliedParams change
//
// URL shape:
//   ?asof=2026-02-26&prev=2026-01-27&mode=movement&window=30d
//   &measure=total_quantity&fields=region:TC,product:T
//   &f=region:AMER,region:EMEA&x=product:WidgetB
// =============================================

const encodeFieldConfigs = (configs: FieldConfig[]): string =>
  configs
    .filter(c => c.showTable || c.showChart)
    .map(c => {
      const flag = c.showTable && c.showChart ? 'TC' : c.showTable ? 'T' : 'C';
      return `${c.field}:${flag}`;
    })
    .join(',');

const decodeFieldConfigs = (raw: string): FieldConfig[] =>
  raw.split(',').map(part => {
    const [field, flag] = part.split(':');
    return {
      field,
      showTable: flag.includes('T'),
      showChart: flag.includes('C'),
    };
  });

const encodeKVPairs = (pairs: Record<string, string[]>): string =>
  Object.entries(pairs)
    .flatMap(([k, vs]) => vs.map(v => `${k}:${v}`))
    .join(',');

const decodeKVPairs = (raw: string): Record<string, string[]> =>
  raw.split(',').reduce((acc, part) => {
    const idx = part.indexOf(':');
    if (idx === -1) return acc;
    const k = part.slice(0, idx);
    const v = part.slice(idx + 1);
    acc[k] = [...(acc[k] ?? []), v];
    return acc;
  }, {} as Record<string, string[]>);

export const serializeToUrl = (params: QueryParams): string => {
  const p = new URLSearchParams();
  if (params.asofDate)    p.set('asof',    params.asofDate);
  if (params.prevDate)    p.set('prev',    params.prevDate);
  if (params.mode)        p.set('mode',    params.mode);
  if (params.chartWindow) p.set('window',  params.chartWindow);
  if (params.measure)     p.set('measure', params.measure);

  if (params.fieldConfigs?.length) {
    const encoded = encodeFieldConfigs(params.fieldConfigs);
    if (encoded) p.set('fields', encoded);
  }

  const fStr = encodeKVPairs(params.filters ?? {});
  if (fStr) p.set('f', fStr);

  const xStr = encodeKVPairs(params.exclusions ?? {});
  if (xStr) p.set('x', xStr);

  return p.toString();
};

export const parseFromUrl = (search: string): Partial<QueryParams> => {
  const p = new URLSearchParams(search);
  const result: Partial<QueryParams> = {};

  const asof = p.get('asof');
  if (asof) result.asofDate = asof;

  const prev = p.get('prev');
  if (prev) result.prevDate = prev;

  const mode = p.get('mode');
  if (mode === 'movement' || mode === 'spot') result.mode = mode;

  const window = p.get('window');
  if (window === '30d' || window === '60d' || window === '90d' || window === '1Y') {
    result.chartWindow = window;
  }

  const measure = p.get('measure');
  if (measure) result.measure = measure;

  const fields = p.get('fields');
  if (fields) result.fieldConfigs = decodeFieldConfigs(fields);

  const f = p.get('f');
  if (f) result.filters = decodeKVPairs(f);

  const x = p.get('x');
  if (x) result.exclusions = decodeKVPairs(x);

  return result;
};

export const pushUrlState = (params: QueryParams): void => {
  const qs = serializeToUrl(params);
  const newUrl = `${window.location.pathname}${qs ? '?' + qs : ''}`;
  window.history.replaceState(null, '', newUrl);
};
