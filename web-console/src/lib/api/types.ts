/**
 * types.ts — Types TypeScript pour les endpoints contexte (W52.a)
 *
 * GET  /v1/me                  → MeResponse
 * POST /v1/auth/select-context → SelectContextResponse
 */

/** Un contexte d'accès disponible pour l'utilisateur connecté. */
export interface MeContext {
  cabinet_id: string;
  cabinet_name?: string;
  role: string;
  secretariat_id?: string;
  secretariat_name?: string;
}

/** Réponse de GET /v1/me (§7 docs/12-reference-api.md). */
export interface MeResponse {
  id: string;
  email: string;
  kind: 'patient' | 'pro';
  role?: 'admin' | 'practitioner' | 'secretary';
  cabinet_id?: string;
  memberships?: Array<{ cabinet_id: string; role: string; secretariat_id?: string }>;
  contexts?: MeContext[];
}

/** Corps de POST /v1/auth/select-context (§3 docs/12-reference-api.md). */
export interface SelectContextRequest {
  cabinet_id: string;
  secretariat_id?: string;
}

/** Réponse de POST /v1/auth/select-context (§3 docs/12-reference-api.md). */
export interface SelectContextResponse {
  access_token: string;
  refresh_token?: string;
}
