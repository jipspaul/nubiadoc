/**
 * context.ts — Client typé pour les endpoints contexte (W52.a)
 *
 * GET  /v1/me                  → getMe()
 * POST /v1/auth/select-context → selectContext()
 *
 * Délèguent à `apiFetch` (gestion 401 → refresh → redirect /login).
 * Pas de fetch ad-hoc : conformément aux règles dures AGENTS.md §3.
 */

import { apiFetch } from '../api';
import type { MeResponse, SelectContextRequest, SelectContextResponse } from './types';

/**
 * GET /v1/me — retourne le profil de l'utilisateur connecté avec ses contextes.
 * Lève une erreur avec le message HTTP en cas de 4xx (hors 401 géré par apiFetch).
 */
export async function getMe(): Promise<MeResponse> {
  const { status, data } = await apiFetch('/v1/me');
  if (status === 200) return data as MeResponse;
  throw new Error(`GET /v1/me a échoué (HTTP ${status})`);
}

/**
 * POST /v1/auth/select-context — sélectionne un contexte cabinet/secrétariat.
 * Lève une erreur avec le message HTTP en cas de 4xx (hors 401 géré par apiFetch).
 */
export async function selectContext(req: SelectContextRequest): Promise<SelectContextResponse> {
  const { status, data } = await apiFetch('/v1/auth/select-context', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(req),
  });
  if (status === 200) return data as SelectContextResponse;
  throw new Error(`POST /v1/auth/select-context a échoué (HTTP ${status})`);
}
