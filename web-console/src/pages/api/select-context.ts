import type { APIRoute } from 'astro';

const API_BASE: string =
  (import.meta.env.PUBLIC_API_BASE as string | undefined) ?? 'http://localhost:38030';

const ROLE_HOME: Record<string, string> = {
  practitioner: '/praticien/dashboard',
  admin: '/praticien/dashboard',
  secretary: '/secretary/dashboard',
};

interface JwtPayload {
  role?: string;
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

export const POST: APIRoute = async ({ request, cookies, redirect }) => {
  // Lire cabinet_id et secretariat_id? depuis le body form
  let cabinet_id: string;
  let secretariat_id: string | undefined;

  const contentType = request.headers.get('content-type') ?? '';
  if (contentType.includes('application/x-www-form-urlencoded')) {
    const text = await request.text();
    const params = new URLSearchParams(text);
    cabinet_id = params.get('cabinet_id') ?? '';
    secretariat_id = params.get('secretariat_id') ?? undefined;
  } else {
    const body = await request.json() as { cabinet_id?: string; secretariat_id?: string };
    cabinet_id = body.cabinet_id ?? '';
    secretariat_id = body.secretariat_id;
  }

  if (!cabinet_id) {
    return redirect('/auth/select-context?error=1', 303);
  }

  // Lire le JWT courant depuis le cookie httpOnly
  const currentJwt = cookies.get('nubia_jwt')?.value;
  if (!currentJwt) {
    return redirect('/auth/login', 303);
  }

  // Appeler POST /v1/auth/select-context
  const apiBody: { cabinet_id: string; secretariat_id?: string } = { cabinet_id };
  if (secretariat_id) apiBody.secretariat_id = secretariat_id;

  let res: Response;
  try {
    res = await fetch(`${API_BASE}/v1/auth/select-context`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${currentJwt}`,
      },
      body: JSON.stringify(apiBody),
    });
  } catch {
    return redirect('/auth/select-context?error=1', 303);
  }

  if (res.status === 401) {
    return redirect('/auth/login', 303);
  }

  if (!res.ok) {
    return redirect('/auth/select-context?error=1', 303);
  }

  const json = await res.json() as { access_token?: string };
  const newToken = json.access_token;
  if (!newToken) {
    return redirect('/auth/select-context?error=1', 303);
  }

  // Poser le nouveau JWT en cookie httpOnly Secure SameSite=Lax
  const cookieOpts = {
    httpOnly: true,
    secure: true,
    sameSite: 'lax' as const,
    path: '/',
  };

  cookies.set('nubia_jwt', newToken, cookieOpts);

  // Décoder le nouveau JWT pour extraire role, cabinet_id, secretariat_id
  const payload = decodePayload(newToken);
  const role = payload?.role ?? '';
  const newCabinetId = payload?.cabinet_id ?? cabinet_id;
  const newSecretariatId = payload?.secretariat_id ?? secretariat_id ?? '';

  if (role) {
    cookies.set('nubia_role', role, { ...cookieOpts, httpOnly: false });
    const ctx = [newCabinetId, role, newSecretariatId].join('|');
    cookies.set('nubia_ctx', ctx, { ...cookieOpts, httpOnly: false });
  }

  const destination = ROLE_HOME[role] ?? '/praticien/dashboard';
  return redirect(destination, 303);
};
