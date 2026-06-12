import type { MeContext, MeResponse } from './endpoints';

const API_BASE: string =
  (import.meta.env.API_BASE as string | undefined) ?? 'http://localhost:38030';

export interface MeResult {
  contexts: MeContext[];
  hasMultiple: boolean;
}

/**
 * SSR — Appelle GET /v1/me avec le JWT de session et retourne les contextes disponibles.
 * Ne lève jamais : renvoie { contexts: [], hasMultiple: false } en cas d'erreur réseau ou API.
 */
export async function fetchMe(jwt: string): Promise<MeResult> {
  try {
    const res = await fetch(`${API_BASE}/v1/me`, {
      headers: { Authorization: `Bearer ${jwt}` },
    });
    if (!res.ok) return { contexts: [], hasMultiple: false };

    const me = (await res.json()) as MeResponse;
    const contexts: MeContext[] =
      me.contexts && me.contexts.length > 0
        ? me.contexts
        : (me.memberships ?? []).map(m => ({ cabinet_id: m.cabinet_id, role: m.role }));

    return { contexts, hasMultiple: contexts.length > 1 };
  } catch {
    return { contexts: [], hasMultiple: false };
  }
}
