/**
 * Helpers métier « cabinet » — couche fine au-dessus de authedFetch.
 *
 * Ces helpers encodent les appels API les plus fréquents dans les scénarios E2E
 * (booking, agenda, confirmation…). Ils prennent un token JWT explicite pour rester
 * indépendants du mécanisme de stockage côté Flutter web (localStorage, IndexedDB…).
 *
 * Usage typique :
 *   const pToken = await loginApi(P_EMAIL, P_PASS);
 *   const appointmentId = await bookAppointment(pToken, { providerId, slotId, motif });
 */

import { authedFetch } from './helpers';

export interface AppointmentOpts {
  /** ID du praticien cible. */
  providerId: string;
  /** ID du créneau sélectionné. */
  slotId: string;
  motif: string;
}

export interface AgendaEvent {
  appointment_id: string;
  status: string;
  date: string;
  slot_id: string;
  provider_id: string;
  [key: string]: unknown;
}

/**
 * Réserve un RDV via l'API patient (POST /v1/appointments → 201).
 * Retourne l'appointment_id du RDV créé.
 */
export async function bookAppointment(
  patientToken: string,
  opts: AppointmentOpts,
): Promise<string> {
  const res = await authedFetch(patientToken, '/appointments', {
    method: 'POST',
    body: JSON.stringify({
      provider_id: opts.providerId,
      slot_id: opts.slotId,
      motif: opts.motif,
    }),
  });
  if (!res.ok) throw new Error(`bookAppointment échoué: HTTP ${res.status}`);
  const body = (await res.json()) as { appointment_id: string };
  return body.appointment_id;
}

/**
 * Retourne les events d'agenda du secrétariat pour une date (GET /v1/cabinet/appointments?date=YYYY-MM-DD).
 */
export async function getAgendaEvents(
  secretariatToken: string,
  date: string,
): Promise<AgendaEvent[]> {
  const res = await authedFetch(secretariatToken, `/cabinet/appointments?date=${date}`);
  if (!res.ok) throw new Error(`getAgendaEvents échoué: HTTP ${res.status}`);
  const body = (await res.json()) as unknown;
  return (Array.isArray(body) ? body : ((body as { data: AgendaEvent[] }).data ?? [])) as AgendaEvent[];
}

/**
 * Confirme un RDV côté secrétariat (POST /v1/cabinet/appointments/:id/confirm → 200).
 */
export async function confirmAppointment(
  secretariatToken: string,
  appointmentId: string,
): Promise<void> {
  const res = await authedFetch(
    secretariatToken,
    `/cabinet/appointments/${appointmentId}/confirm`,
    { method: 'POST' },
  );
  if (!res.ok) throw new Error(`confirmAppointment échoué: HTTP ${res.status}`);
}

/**
 * Annule un RDV côté patient (POST /v1/appointments/:id/cancel → 200).
 */
export async function cancelAppointment(
  patientToken: string,
  appointmentId: string,
  raison: string,
): Promise<void> {
  const res = await authedFetch(
    patientToken,
    `/appointments/${appointmentId}/cancel`,
    { method: 'POST', body: JSON.stringify({ raison }) },
  );
  if (!res.ok) throw new Error(`cancelAppointment échoué: HTTP ${res.status}`);
}
