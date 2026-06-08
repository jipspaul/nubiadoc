export interface Session {
  email: string;
  kind: 'patient' | 'pro';
  role: 'admin' | 'practitioner' | 'secretary' | null;
  account_id: string | null;
  cabinet_id: string | null;
  secretariat_id: string | null;
}

export interface Context {
  cabinet_id: string;
  role: string;
  secretariat_id?: string;
}

const CTX_KEY = 'nubia_ctx';

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
  secretariat_id?: string;
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
    if (payload.cabinet_id && payload.role) {
      const parts = [payload.cabinet_id, payload.role, payload.secretariat_id ?? ''].join('|');
      document.cookie = `${CTX_KEY}=${parts}; path=/; SameSite=Strict`;
    }
  }
}

export function logout(): void {
  localStorage.removeItem(JWT_KEY);
  document.cookie = `${JWT_KEY}=; path=/; max-age=0`;
  document.cookie = `${ROLE_KEY}=; path=/; max-age=0`;
  document.cookie = `${CTX_KEY}=; path=/; max-age=0`;
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
    secretariat_id: payload.secretariat_id ?? null,
  };
}

/** Retourne le contexte actif {cabinet_id, role, secretariat_id?} depuis le JWT courant. */
export function getContext(): Context | null {
  const token = localStorage.getItem(JWT_KEY);
  if (!token) return null;
  const payload = decodePayload(token);
  if (!payload?.cabinet_id || !payload.role) return null;
  const ctx: Context = { cabinet_id: payload.cabinet_id, role: payload.role };
  if (payload.secretariat_id) ctx.secretariat_id = payload.secretariat_id;
  return ctx;
}

/** Retourne true ssi cabinet_id et role sont présents dans le JWT courant. */
export function hasContext(): boolean {
  return getContext() !== null;
}

/** Supprime nubia_ctx et purge le token en mémoire. */
export function clearContext(): void {
  localStorage.removeItem(JWT_KEY);
  document.cookie = `${CTX_KEY}=; path=/; max-age=0`;
}

/** Rétro-compat : retourne l'email de l'utilisateur courant. */
export function getCurrentUser(): string | null {
  return getSession()?.email ?? null;
}
