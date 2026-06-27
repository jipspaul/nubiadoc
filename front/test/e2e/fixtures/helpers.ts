import { request as playwrightRequest } from '@playwright/test';

export const API = process.env.API_BASE_URL ?? 'http://localhost:8080/v1';

/**
 * Authentifie via POST /v1/auth/login et retourne l'access_token JWT.
 * Lève une erreur si le login échoue (backend inaccessible ou credentials invalides).
 */
export async function loginApi(email: string, password: string): Promise<string> {
  const ctx = await playwrightRequest.newContext();
  try {
    const res = await ctx.post(`${API}/auth/login`, {
      data: { email, password },
    });
    if (!res.ok()) {
      throw new Error(`Login échoué pour ${email}: HTTP ${res.status()}`);
    }
    const body = await res.json();
    return body.access_token as string;
  } finally {
    await ctx.dispose();
  }
}

/**
 * Effectue un fetch authentifié vers l'API.
 * Délègue à l'API fetch native du runtime (Node 18+/Playwright).
 */
export function authedFetch(
  token: string,
  path: string,
  options?: RequestInit,
): Promise<Response> {
  return fetch(`${API}${path}`, {
    method: 'GET',
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(options?.headers as Record<string, string>),
    },
  });
}
