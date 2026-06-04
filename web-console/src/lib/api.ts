const API_BASE: string =
  (import.meta.env.PUBLIC_API_BASE as string | undefined) ?? 'http://localhost:3000';

export async function apiFetch(
  path: string,
  options: RequestInit = {},
): Promise<{ status: number; data: unknown }> {
  const res = await fetch(`${API_BASE}${path}`, options);
  const data: unknown = await res.json();
  return { status: res.status, data };
}
