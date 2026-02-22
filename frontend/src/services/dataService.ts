// dataService.ts
// Base HTTP helpers for all KDB+ server calls
// All data endpoints use POST with JSON body; catalog endpoints use GET

const BASE_URL = 'http://localhost:5010';

// GET request — used for catalog endpoints
export const kdbGet = async <T>(endpoint: string): Promise<T> => {
  const res = await fetch(`${BASE_URL}${endpoint}`, {
    method: 'GET',
    headers: { 'Content-Type': 'application/json' },
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: res.statusText }));
    throw new Error(`KDB+ GET ${endpoint} failed (${res.status}): ${err.message ?? res.statusText}`);
  }
  return res.json() as Promise<T>;
};

// POST request — used for query endpoints
export const kdbPost = async <T>(endpoint: string, body: Record<string, unknown>): Promise<T> => {
  const res = await fetch(`${BASE_URL}${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: res.statusText }));
    throw new Error(`KDB+ POST ${endpoint} failed (${res.status}): ${err.message ?? res.statusText}`);
  }
  return res.json() as Promise<T>;
};
