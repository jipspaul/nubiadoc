const API_BASE: string =
  (import.meta.env.PUBLIC_API_BASE as string | undefined) ?? 'http://localhost:3000';

const JWT_KEY = 'nubia_jwt';
const REFRESH_KEY = 'nubia_refresh_token';

function getAccessToken(): string | null {
  if (typeof localStorage === 'undefined') return null;
  return localStorage.getItem(JWT_KEY);
}

function getRefreshToken(): string | null {
  if (typeof localStorage === 'undefined') return null;
  return localStorage.getItem(REFRESH_KEY);
}

function purgeSession(): void {
  if (typeof localStorage === 'undefined') return;
  localStorage.removeItem(JWT_KEY);
  localStorage.removeItem(REFRESH_KEY);
  document.cookie = `${JWT_KEY}=; path=/; max-age=0`;
  document.cookie = `nubia_role=; path=/; max-age=0`;
}

async function refreshTokens(): Promise<boolean> {
  const refreshToken = getRefreshToken();
  if (!refreshToken) return false;

  const res = await fetch(`${API_BASE}/v1/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });

  if (!res.ok) return false;

  const text = await res.text();
  if (!text) return false;

  const data = JSON.parse(text) as { access_token?: string; refresh_token?: string };
  if (!data.access_token) return false;

  localStorage.setItem(JWT_KEY, data.access_token);
  document.cookie = `${JWT_KEY}=${data.access_token}; path=/; SameSite=Strict`;
  if (data.refresh_token) {
    localStorage.setItem(REFRESH_KEY, data.refresh_token);
  }

  return true;
}

export async function apiFetch(
  path: string,
  options: RequestInit = {},
): Promise<{ status: number; data: unknown }> {
  const token = getAccessToken();
  const headers = new Headers(options.headers);
  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const res = await fetch(`${API_BASE}${path}`, { ...options, headers });

  if (res.status !== 401) {
    const text = await res.text();
    const data: unknown = text ? JSON.parse(text) : null;
    return { status: res.status, data };
  }

  // 401 — attempt refresh and replay once
  const refreshed = await refreshTokens();
  if (!refreshed) {
    purgeSession();
    if (typeof window !== 'undefined') {
      window.location.href = '/auth/login';
    }
    return { status: 401, data: null };
  }

  const newToken = getAccessToken();
  const retryHeaders = new Headers(options.headers);
  if (newToken) {
    retryHeaders.set('Authorization', `Bearer ${newToken}`);
  }

  const retryRes = await fetch(`${API_BASE}${path}`, { ...options, headers: retryHeaders });
  const retryText = await retryRes.text();
  const retryData: unknown = retryText ? JSON.parse(retryText) : null;

  if (retryRes.status === 401) {
    purgeSession();
    if (typeof window !== 'undefined') {
      window.location.href = '/auth/login';
    }
  }

  return { status: retryRes.status, data: retryData };
}
