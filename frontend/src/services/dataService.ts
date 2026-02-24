const BASE_URL = '/api';

export const kdbGet = async <T>(endpoint: string): Promise<T> => {
  const res = await fetch(`${BASE_URL}${endpoint}`);
  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: res.statusText }));
    throw new Error(`KDB+ GET ${endpoint} failed (${res.status}): ${err.message ?? res.statusText}`);
  }
  return res.json() as Promise<T>;
};

// _route is embedded in body so kdb+ .z.pp can dispatch correctly
// (kdb+ 4.x .z.pp only receives body, not the URL path)
export const kdbPost = async <T>(endpoint: string, body: Record<string, unknown>): Promise<T> => {
  const res = await fetch(`${BASE_URL}${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ ...body, _route: endpoint }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: res.statusText }));
    throw new Error(`KDB+ POST ${endpoint} failed (${res.status}): ${err.message ?? res.statusText}`);
  }
  return res.json() as Promise<T>;
};
