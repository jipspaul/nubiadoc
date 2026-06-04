export interface User { email: string }

const JWT_KEY = 'nubia_jwt';

export function login(token: string): void {
  localStorage.setItem(JWT_KEY, token);
  document.cookie = `${JWT_KEY}=${token}; path=/; SameSite=Strict`;
}

export function logout(): void {
  localStorage.removeItem(JWT_KEY);
  document.cookie = `${JWT_KEY}=; path=/; max-age=0`;
}

export function isAuthenticated(): boolean {
  return localStorage.getItem(JWT_KEY) !== null;
}

export function getCurrentUser(): string | null {
  const token = localStorage.getItem(JWT_KEY);
  if (!token) return null;
  try {
    const parts = token.split('.');
    if (parts.length < 2) return null;
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    return (payload as { email?: string }).email ?? null;
  } catch {
    return null;
  }
}
