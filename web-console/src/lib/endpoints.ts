/**
 * endpoints.ts — Client typé par domaine (W4)
 *
 * Toutes les fonctions délèguent à `apiFetch` (W3) et retournent `{status, data}`.
 * Couche purement HTTP : pas de cookie, pas de localStorage.
 * Domaines : auth, patient.account, patient.appointments, patient.documents,
 *   patient.conversations, patient.dashboard, patient.quotes, patient.treatmentPlans,
 *   search, pro.cabinet, pro.agenda, pro.patients, pro.consultations, pro.prescriptions.
 */

import { apiFetch } from './api';

// ---------------------------------------------------------------------------
// Types partagés
// ---------------------------------------------------------------------------

export interface ApiResponse<T = unknown> {
  status: number;
  data: T;
}

// Auth
export interface AuthTokens {
  access_token: string;
  refresh_token?: string;
}

export interface MeResponse {
  id: string;
  email: string;
  kind: 'patient' | 'pro';
  role?: 'admin' | 'practitioner' | 'secretary';
  cabinet_id?: string;
  memberships?: Array<{ cabinet_id: string; role: string }>;
}

// Patient — compte
export interface PatientAccount {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  phone?: string;
  date_of_birth?: string;
}

export interface Coverage {
  regime?: string;
  mutual?: string;
  mutual_number?: string;
}

export interface Dependent {
  id: string;
  first_name: string;
  last_name: string;
  date_of_birth?: string;
  relationship?: string;
}

export interface NotificationPreferences {
  email: boolean;
  sms: boolean;
  push: boolean;
}

export interface Consent {
  purpose: string;
  granted: boolean;
  updated_at?: string;
}

// Patient — RDV
export interface Appointment {
  id: string;
  status: string;
  scheduled_at: string;
  provider_id?: string;
  cabinet_id?: string;
  patient_id?: string;
  notes?: string;
}

export interface AppointmentPreparation {
  instructions?: string;
  documents_needed?: string[];
}

export interface AppointmentDirections {
  address?: string;
  map_url?: string;
}

export interface QueuePosition {
  position?: number;
  estimated_wait_minutes?: number;
}

// Patient — documents
export interface Document {
  id: string;
  name: string;
  type?: string;
  created_at?: string;
}

// Patient — conversations
export interface Conversation {
  id: string;
  subject?: string;
  last_message_at?: string;
  unread_count?: number;
  scope?: 'clinical' | 'admin';
}

export interface Message {
  id: string;
  body: string;
  sender_id: string;
  sent_at: string;
}

// Patient — dashboard
export interface Dashboard {
  next_appointment?: Appointment & { provider_name?: string };
  unread_messages?: number;
  /** Legacy flat count (pre-contract). */
  pending_quotes?: number;
  pending_signatures?: number;
  /** Contract per docs/12: array of quotes awaiting signature. */
  to_sign?: Array<{ quote_id: string }>;
  /** Contract per docs/12: array of payments due. */
  to_pay?: Array<{ amount_cents: number }>;
}

// Patient — finances / soins
export interface Quote {
  id: string;
  status: string;
  total_amount?: number;
  created_at?: string;
}

export interface TreatmentPlan {
  id: string;
  title?: string;
  status?: string;
  created_at?: string;
}

export interface ImplantPassport {
  id: string;
  implants?: Array<{ type: string; position?: string; placed_at?: string }>;
}

export interface PaymentIntent {
  payment_id: string;
  client_secret: string;
}

// Search / marketplace public
export interface SearchSuggest {
  suggestions: string[];
}

export interface SearchProviders {
  providers: Provider[];
  total?: number;
}

export interface SearchSlots {
  slots: Slot[];
}

export interface Provider {
  id: string;
  first_name?: string;
  last_name?: string;
  specialty?: string;
  cabinet_id?: string;
}

export interface Slot {
  id: string;
  starts_at: string;
  duration_minutes?: number;
  provider_id?: string;
}

export interface CabinetInfo {
  id: string;
  name?: string;
  address?: string;
  phone?: string;
}

export interface Profession {
  id: string;
  label: string;
}

export interface Specialty {
  id: string;
  label: string;
}

export interface Act {
  id: string;
  code?: string;
  label: string;
}

export interface Review {
  id: string;
  rating: number;
  comment?: string;
  created_at?: string;
}

// Pro — cabinet
export interface Cabinet {
  id: string;
  name?: string;
  address?: string;
  phone?: string;
  siret?: string;
}

export interface CabinetMember {
  user_id: string;
  email?: string;
  role: 'admin' | 'practitioner' | 'secretary';
  active?: boolean;
}

export interface CabinetPatient {
  id: string;
  first_name?: string;
  last_name?: string;
  email?: string;
  date_of_birth?: string;
}

export interface PatientNote {
  id: string;
  body: string;
  created_at?: string;
  author_id?: string;
}

export interface MedicalRecord {
  allergies?: string[];
  current_medications?: string[];
  history?: string;
}

export interface DentalChart {
  teeth?: Array<{ number: number; status?: string; notes?: string }>;
}

// Pro — consultations
export interface Consultation {
  id: string;
  appointment_id?: string;
  status?: string;
  started_at?: string;
  completed_at?: string;
}

export interface ConsultationAct {
  code: string;
  label?: string;
  quantity?: number;
}

// Pro — prescriptions
export interface Prescription {
  id: string;
  patient_id?: string;
  lines?: Array<{ drug: string; dosage?: string; duration?: string }>;
  signed?: boolean;
  signed_at?: string;
}

// Pro — agenda
export interface AgendaEntry {
  date: string;
  slots?: Slot[];
  appointments?: Appointment[];
}

export interface WaitingRoomEntry {
  id: string;
  patient_id?: string;
  checked_in_at?: string;
  position?: number;
}

export interface WaitingListEntry {
  id: string;
  patient_id?: string;
  requested_at?: string;
  status?: string;
}

// Pro — secretariats
export interface Secretariat {
  id: string;
  name?: string;
  cabinet_id?: string;
}

// Pro — quotes (secrétariat / praticien)
export interface CabinetQuote {
  id: string;
  patient_id?: string;
  patient_name?: string;
  status: string;
  total_amount?: number;
  created_at?: string;
}

// Pro — provider listing
export interface Provider_listing {
  is_listed: boolean;
  bio?: string;
  languages?: string[];
}

export interface ProVerification {
  status?: 'pending' | 'verified' | 'rejected';
  rpps?: string;
  submitted_at?: string;
}

// ---------------------------------------------------------------------------
// auth
// ---------------------------------------------------------------------------

export const auth = {
  register: (body: { email: string; password: string; first_name?: string; last_name?: string }) =>
    apiFetch('/v1/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<AuthTokens>>,

  login: (body: { email: string; password: string; mfa_code?: string }) =>
    apiFetch('/v1/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<AuthTokens>>,

  refresh: (body: { refresh_token: string }) =>
    apiFetch('/v1/auth/refresh', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<AuthTokens>>,

  logout: () =>
    apiFetch('/v1/auth/logout', { method: 'POST' }) as Promise<ApiResponse<null>>,

  mfaEnroll: () =>
    apiFetch('/v1/auth/mfa/enroll', { method: 'POST' }) as Promise<ApiResponse<{ secret: string; qr_url: string }>>,

  mfaVerify: (body: { code: string }) =>
    apiFetch('/v1/auth/mfa/verify', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<null>>,

  passwordForgot: (body: { email: string }) =>
    apiFetch('/v1/auth/password/forgot', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<null>>,

  passwordReset: (body: { token: string; password: string }) =>
    apiFetch('/v1/auth/password/reset', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<null>>,

  me: () =>
    apiFetch('/v1/me') as Promise<ApiResponse<MeResponse>>,
};

// ---------------------------------------------------------------------------
// patient.account
// ---------------------------------------------------------------------------

export const patientAccount = {
  get: () =>
    apiFetch('/v1/account') as Promise<ApiResponse<PatientAccount>>,

  patch: (body: Partial<PatientAccount>) =>
    apiFetch('/v1/account', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<PatientAccount>>,

  getCoverage: () =>
    apiFetch('/v1/account/coverage') as Promise<ApiResponse<Coverage>>,

  patchCoverage: (body: Partial<Coverage>) =>
    apiFetch('/v1/account/coverage', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Coverage>>,

  postCoverageCard: (body: FormData) =>
    apiFetch('/v1/account/coverage/card', { method: 'POST', body }) as Promise<ApiResponse<{ url: string }>>,

  getNotificationPreferences: () =>
    apiFetch('/v1/account/notification-preferences') as Promise<ApiResponse<NotificationPreferences>>,

  patchNotificationPreferences: (body: Partial<NotificationPreferences>) =>
    apiFetch('/v1/account/notification-preferences', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<NotificationPreferences>>,

  getDependents: () =>
    apiFetch('/v1/account/dependents') as Promise<ApiResponse<Dependent[]>>,

  postDependent: (body: Omit<Dependent, 'id'>) =>
    apiFetch('/v1/account/dependents', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Dependent>>,

  getDependent: (id: string) =>
    apiFetch(`/v1/account/dependents/${id}`) as Promise<ApiResponse<Dependent>>,

  patchDependent: (id: string, body: Partial<Dependent>) =>
    apiFetch(`/v1/account/dependents/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Dependent>>,

  deleteDependent: (id: string) =>
    apiFetch(`/v1/account/dependents/${id}`, { method: 'DELETE' }) as Promise<ApiResponse<null>>,

  getConsents: () =>
    apiFetch('/v1/account/consents') as Promise<ApiResponse<Consent[]>>,

  putConsent: (purpose: string, body: { granted: boolean }) =>
    apiFetch(`/v1/account/consents/${purpose}`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Consent>>,
};

// ---------------------------------------------------------------------------
// patient.appointments
// ---------------------------------------------------------------------------

export const patientAppointments = {
  list: (params?: { status?: string }) => {
    const qs = params?.status ? `?status=${params.status}` : '';
    return apiFetch(`/v1/appointments${qs}`) as Promise<ApiResponse<Appointment[]>>;
  },

  post: (body: { provider_id: string; scheduled_at: string; notes?: string }) =>
    apiFetch('/v1/appointments', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Appointment>>,

  get: (id: string) =>
    apiFetch(`/v1/appointments/${id}`) as Promise<ApiResponse<Appointment>>,

  patch: (id: string, body: Partial<Appointment>) =>
    apiFetch(`/v1/appointments/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Appointment>>,

  cancel: (id: string) =>
    apiFetch(`/v1/appointments/${id}/cancel`, { method: 'POST' }) as Promise<ApiResponse<null>>,

  checkin: (id: string) =>
    apiFetch(`/v1/appointments/${id}/checkin`, { method: 'POST' }) as Promise<ApiResponse<null>>,

  callbackRequest: (id: string) =>
    apiFetch(`/v1/appointments/${id}/callback-request`, { method: 'POST' }) as Promise<ApiResponse<null>>,

  getDirections: (id: string) =>
    apiFetch(`/v1/appointments/${id}/directions`) as Promise<ApiResponse<AppointmentDirections>>,

  getPreparation: (id: string) =>
    apiFetch(`/v1/appointments/${id}/preparation`) as Promise<ApiResponse<AppointmentPreparation>>,

  getQueue: (id: string) =>
    apiFetch(`/v1/appointments/${id}/queue`) as Promise<ApiResponse<QueuePosition>>,
};

// ---------------------------------------------------------------------------
// patient.documents
// ---------------------------------------------------------------------------

export const patientDocuments = {
  list: () =>
    apiFetch('/v1/documents') as Promise<ApiResponse<Document[]>>,

  post: (body: FormData) =>
    apiFetch('/v1/documents', { method: 'POST', body }) as Promise<ApiResponse<Document>>,

  get: (id: string) =>
    apiFetch(`/v1/documents/${id}`) as Promise<ApiResponse<Document>>,

  download: (id: string) =>
    apiFetch(`/v1/documents/${id}/download`) as Promise<ApiResponse<{ url: string }>>,
};

// ---------------------------------------------------------------------------
// patient.conversations
// ---------------------------------------------------------------------------

export const patientConversations = {
  list: () =>
    apiFetch('/v1/conversations') as Promise<ApiResponse<Conversation[]>>,

  post: (body: { subject?: string; cabinet_id: string }) =>
    apiFetch('/v1/conversations', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Conversation>>,

  getMessages: (id: string) =>
    apiFetch(`/v1/conversations/${id}/messages`) as Promise<ApiResponse<Message[]>>,

  postMessage: (id: string, body: { body: string }) =>
    apiFetch(`/v1/conversations/${id}/messages`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Message>>,

  markRead: (id: string) =>
    apiFetch(`/v1/conversations/${id}/read`, { method: 'POST' }) as Promise<ApiResponse<null>>,
};

// ---------------------------------------------------------------------------
// patient.dashboard
// ---------------------------------------------------------------------------

export const patientDashboard = {
  get: () =>
    apiFetch('/v1/dashboard') as Promise<ApiResponse<Dashboard>>,

  getNotifications: () =>
    apiFetch('/v1/notifications') as Promise<ApiResponse<Array<{ id: string; type: string; read: boolean; created_at: string }>>>,

  getReminders: () =>
    apiFetch('/v1/reminders') as Promise<ApiResponse<Array<{ id: string; message: string; due_at: string }>>>,
};

// ---------------------------------------------------------------------------
// patient.quotes
// ---------------------------------------------------------------------------

export const patientQuotes = {
  list: () =>
    apiFetch('/v1/quotes') as Promise<ApiResponse<Quote[]>>,

  sign: (id: string) =>
    apiFetch(`/v1/quotes/${id}/signature`, { method: 'POST' }) as Promise<ApiResponse<{ signature_id: string; redirect_url?: string; embed_token?: string }>>,

  createPaymentIntent: (body: { quote_id: string; kind: 'deposit' | 'installment' | 'full'; amount_cents: number; method: 'card' | 'apple_pay' | 'google_pay' | 'sepa'; idempotency_key: string }) =>
    apiFetch('/v1/payments/intent', { method: 'POST', headers: { 'Content-Type': 'application/json', 'Idempotency-Key': body.idempotency_key }, body: JSON.stringify({ quote_id: body.quote_id, kind: body.kind, amount_cents: body.amount_cents, method: body.method }) }) as Promise<ApiResponse<PaymentIntent>>,
};

// ---------------------------------------------------------------------------
// patient.treatmentPlans
// ---------------------------------------------------------------------------

export const patientTreatmentPlans = {
  list: () =>
    apiFetch('/v1/treatment-plans') as Promise<ApiResponse<TreatmentPlan[]>>,

  get: (id: string) =>
    apiFetch(`/v1/treatment-plans/${id}`) as Promise<ApiResponse<TreatmentPlan>>,

  getImplantPassport: () =>
    apiFetch('/v1/implant-passport') as Promise<ApiResponse<ImplantPassport>>,

  exportImplantPassport: () =>
    apiFetch('/v1/implant-passport/export') as Promise<ApiResponse<{ url: string }>>,
};

// ---------------------------------------------------------------------------
// search (marketplace public)
// ---------------------------------------------------------------------------

export const search = {
  suggest: (q: string) =>
    apiFetch(`/v1/search/suggest?q=${encodeURIComponent(q)}`) as Promise<ApiResponse<SearchSuggest>>,

  providers: (params: { q?: string; specialty?: string; lat?: number; lng?: number }) => {
    const qs = new URLSearchParams(Object.entries(params).filter(([, v]) => v != null).map(([k, v]) => [k, String(v)])).toString();
    return apiFetch(`/v1/search/providers${qs ? `?${qs}` : ''}`) as Promise<ApiResponse<SearchProviders>>;
  },

  slots: (params: { provider_id?: string; from?: string; to?: string }) => {
    const qs = new URLSearchParams(Object.entries(params).filter(([, v]) => v != null).map(([k, v]) => [k, String(v)])).toString();
    return apiFetch(`/v1/search/slots${qs ? `?${qs}` : ''}`) as Promise<ApiResponse<SearchSlots>>;
  },

  getProvider: (id: string) =>
    apiFetch(`/v1/providers/${id}`) as Promise<ApiResponse<Provider>>,

  getProviderReviews: (id: string) =>
    apiFetch(`/v1/providers/${id}/reviews`) as Promise<ApiResponse<Review[]>>,

  postReview: (body: { provider_id: string; rating: number; comment?: string }) =>
    apiFetch('/v1/reviews', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Review>>,

  getCabinetInfo: (id: string) =>
    apiFetch(`/v1/cabinets/${id}/info`) as Promise<ApiResponse<CabinetInfo>>,

  getProfessions: () =>
    apiFetch('/v1/professions') as Promise<ApiResponse<Profession[]>>,

  getSpecialties: () =>
    apiFetch('/v1/specialties') as Promise<ApiResponse<Specialty[]>>,

  getActs: () =>
    apiFetch('/v1/acts') as Promise<ApiResponse<Act[]>>,
};

// ---------------------------------------------------------------------------
// pro.cabinet
// ---------------------------------------------------------------------------

export const proCabinet = {
  get: () =>
    apiFetch('/v1/cabinet') as Promise<ApiResponse<Cabinet>>,

  patch: (body: Partial<Cabinet>) =>
    apiFetch('/v1/cabinet', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Cabinet>>,

  patchProvider: (body: Partial<Provider>) =>
    apiFetch('/v1/cabinet/provider', { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Provider>>,

  putProviderListing: (body: Partial<Provider_listing>) =>
    apiFetch('/v1/cabinet/provider/listing', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Provider_listing>>,

  getMembers: () =>
    apiFetch('/v1/cabinet/members') as Promise<ApiResponse<CabinetMember[]>>,

  postMember: (body: { email: string; role: 'practitioner' | 'secretary' }) =>
    apiFetch('/v1/cabinet/members', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<CabinetMember>>,

  patchMember: (userId: string, body: { role?: CabinetMember['role']; active?: boolean }) =>
    apiFetch(`/v1/cabinet/members/${userId}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<CabinetMember>>,

  deleteMember: (userId: string) =>
    apiFetch(`/v1/cabinet/members/${userId}`, { method: 'DELETE' }) as Promise<ApiResponse<null>>,

  getVerification: () =>
    apiFetch('/v1/pro/verification') as Promise<ApiResponse<ProVerification>>,

  postVerification: (body: { rpps: string }) =>
    apiFetch('/v1/pro/verification', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<ProVerification>>,
};

// ---------------------------------------------------------------------------
// pro.agenda
// ---------------------------------------------------------------------------

export const proAgenda = {
  get: (params?: { from?: string; to?: string }) => {
    const qs = params ? new URLSearchParams(Object.entries(params).filter(([, v]) => v != null).map(([k, v]) => [k, String(v)])).toString() : '';
    return apiFetch(`/v1/cabinet/agenda${qs ? `?${qs}` : ''}`) as Promise<ApiResponse<AgendaEntry[]>>;
  },

  getAppointments: (params?: { status?: string }) => {
    const qs = params?.status ? `?status=${params.status}` : '';
    return apiFetch(`/v1/cabinet/appointments${qs}`) as Promise<ApiResponse<Appointment[]>>;
  },

  confirmAppointment: (id: string) =>
    apiFetch(`/v1/cabinet/appointments/${id}/confirm`, { method: 'POST' }) as Promise<ApiResponse<Appointment>>,

  startAppointment: (id: string) =>
    apiFetch(`/v1/cabinet/appointments/${id}/start`, { method: 'POST' }) as Promise<ApiResponse<Appointment>>,

  patchAppointment: (id: string, body: Partial<Appointment>) =>
    apiFetch(`/v1/cabinet/appointments/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Appointment>>,

  getWaitingRoom: () =>
    apiFetch('/v1/cabinet/waiting-room') as Promise<ApiResponse<WaitingRoomEntry[]>>,

  callNext: () =>
    apiFetch('/v1/cabinet/waiting-room/call-next', { method: 'POST' }) as Promise<ApiResponse<WaitingRoomEntry>>,

  getWaitingList: () =>
    apiFetch('/v1/cabinet/waiting-list') as Promise<ApiResponse<WaitingListEntry[]>>,

  offerWaitingList: (id: string) =>
    apiFetch(`/v1/cabinet/waiting-list/${id}/offer`, { method: 'POST' }) as Promise<ApiResponse<null>>,

  postSlot: (body: { starts_at: string; duration_minutes: number; online?: boolean }) =>
    apiFetch('/v1/cabinet/slots', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Slot>>,

  patchSlot: (id: string, body: Partial<Slot>) =>
    apiFetch(`/v1/cabinet/slots/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Slot>>,

  deleteSlot: (id: string) =>
    apiFetch(`/v1/cabinet/slots/${id}`, { method: 'DELETE' }) as Promise<ApiResponse<null>>,

  setSlotOnline: (id: string, body: { online: boolean }) =>
    apiFetch(`/v1/cabinet/slots/${id}/online`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Slot>>,

  getConversations: () =>
    apiFetch('/v1/cabinet/conversations') as Promise<ApiResponse<Conversation[]>>,
};

// ---------------------------------------------------------------------------
// pro.patients
// ---------------------------------------------------------------------------

export const proPatients = {
  list: () =>
    apiFetch('/v1/cabinet/patients') as Promise<ApiResponse<CabinetPatient[]>>,

  get: (id: string) =>
    apiFetch(`/v1/cabinet/patients/${id}`) as Promise<ApiResponse<CabinetPatient>>,

  getNotes: (id: string) =>
    apiFetch(`/v1/cabinet/patients/${id}/notes`) as Promise<ApiResponse<PatientNote[]>>,

  postNote: (id: string, body: { body: string }) =>
    apiFetch(`/v1/cabinet/patients/${id}/notes`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<PatientNote>>,

  getMedicalRecord: (id: string) =>
    apiFetch(`/v1/cabinet/patients/${id}/medical-record`) as Promise<ApiResponse<MedicalRecord>>,

  patchMedicalRecord: (id: string, body: Partial<MedicalRecord>) =>
    apiFetch(`/v1/cabinet/patients/${id}/medical-record`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<MedicalRecord>>,

  getDentalChart: (id: string) =>
    apiFetch(`/v1/cabinet/patients/${id}/dental-chart`) as Promise<ApiResponse<DentalChart>>,

  putDentalChart: (id: string, body: DentalChart) =>
    apiFetch(`/v1/cabinet/patients/${id}/dental-chart`, { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<DentalChart>>,

  getDocuments: (id: string) =>
    apiFetch(`/v1/cabinet/patients/${id}/documents`) as Promise<ApiResponse<Document[]>>,

  postDocument: (id: string, body: FormData) =>
    apiFetch(`/v1/cabinet/patients/${id}/documents`, { method: 'POST', body }) as Promise<ApiResponse<Document>>,
};

// ---------------------------------------------------------------------------
// pro.consultations
// ---------------------------------------------------------------------------

export const proConsultations = {
  get: (id: string) =>
    apiFetch(`/v1/cabinet/consultations/${id}`) as Promise<ApiResponse<Consultation>>,

  postAct: (id: string, body: ConsultationAct) =>
    apiFetch(`/v1/cabinet/consultations/${id}/acts`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<ConsultationAct>>,

  complete: (id: string) =>
    apiFetch(`/v1/cabinet/consultations/${id}/complete`, { method: 'POST' }) as Promise<ApiResponse<Consultation>>,
};

// ---------------------------------------------------------------------------
// pro.prescriptions
// ---------------------------------------------------------------------------

export const proPrescriptions = {
  post: (body: Omit<Prescription, 'id' | 'signed' | 'signed_at'>) =>
    apiFetch('/v1/cabinet/prescriptions', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }) as Promise<ApiResponse<Prescription>>,

  sign: (id: string) =>
    apiFetch(`/v1/cabinet/prescriptions/${id}/sign`, { method: 'POST' }) as Promise<ApiResponse<Prescription>>,
};

// ---------------------------------------------------------------------------
// pro.quotes
// ---------------------------------------------------------------------------

export const proQuotes = {
  list: (params?: { status?: string }) => {
    const qs = params?.status ? `?status=${encodeURIComponent(params.status)}` : '';
    return apiFetch(`/v1/cabinet/quotes${qs}`) as Promise<ApiResponse<CabinetQuote[]>>;
  },
};

// ---------------------------------------------------------------------------
// pro.secretariats
// ---------------------------------------------------------------------------

export const proSecretariats = {
  /** GET /v1/cabinet/secretariats — liste les secrétariats de l'établissement actif */
  list: () =>
    apiFetch('/v1/cabinet/secretariats') as Promise<ApiResponse<Secretariat[]>>,

  /** GET /v1/cabinet/providers/:id/secretariats — secrétariats assignés à un praticien */
  getForProvider: (providerId: string) =>
    apiFetch(`/v1/cabinet/providers/${providerId}/secretariats`) as Promise<ApiResponse<Secretariat[]>>,

  /** PUT /v1/cabinet/providers/:id/secretariats — (ré)assigne le praticien à une liste de secrétariats */
  putForProvider: (providerId: string, body: { secretariat_ids: string[] }) =>
    apiFetch(`/v1/cabinet/providers/${providerId}/secretariats`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }) as Promise<ApiResponse<Secretariat[]>>,
};
