export interface Session {
  email: string;
  kind: 'patient' | 'pro';
  role: 'admin' | 'practitioner' | 'secretary' | null;
  account_id: string | null;
  cabinet_id: string | null;
}

/** Rétro-compat : type User = email seul */
export interface User { email: string }

const JWT_KEY = 'nubia_jwt';
const ROLE_KEY = 'nubia_role';

interface JwtPayload {
  email?: string;
  kind?: string;
  role?: string;
  account_id?: string;
  cabinet_id?: string;
}

function decodePayload(token: string): JwtPayload | null {
  try {
    const parts = token.split('.');
    if (parts.length < 2) return null;
    return JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/'))) as JwtPayload;
  } catch {
    return null;
  }
}

export function login(token: string): void {
  localStorage.setItem(JWT_KEY, token);
  document.cookie = `${JWT_KEY}=${token}; path=/; SameSite=Strict`;

  const payload = decodePayload(token);
  if (payload) {
    const effectiveRole = payload.kind === 'patient' ? 'patient' : (payload.role ?? '');
    if (effectiveRole) {
      document.cookie = `${ROLE_KEY}=${effectiveRole}; path=/; SameSite=Strict`;
    }
  }
}

export function logout(): void {
  localStorage.removeItem(JWT_KEY);
  document.cookie = `${JWT_KEY}=; path=/; max-age=0`;
  document.cookie = `${ROLE_KEY}=; path=/; max-age=0`;
}

export function isAuthenticated(): boolean {
  return localStorage.getItem(JWT_KEY) !== null;
}

/** Retourne la session complète ou null si non authentifié / token invalide. */
export function getSession(): Session | null {
  const token = localStorage.getItem(JWT_KEY);
  if (!token) return null;
  const payload = decodePayload(token);
  if (!payload || !payload.email) return null;
  return {
    email: payload.email,
    kind: payload.kind === 'pro' ? 'pro' : 'patient',
    role: (payload.role as Session['role']) ?? null,
    account_id: payload.account_id ?? null,
    cabinet_id: payload.cabinet_id ?? null,
  };
}

/** Rétro-compat : retourne l'email de l'utilisateur courant. */
export function getCurrentUser(): string | null {
  return getSession()?.email ?? null;
}
