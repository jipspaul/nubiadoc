//! `/v1/interop/fhir/Appointment` — lecture/écriture FHIR des rendez-vous (lot A6).
//!
//! ## Chemin volontairement séparé de `appointments_create.rs`/`scheduling.rs`
//!
//! Ce module N'appelle PAS `appointments_create::create_appointment` (patient) ni
//! `scheduling::create_cabinet_appointment` (secrétariat), et ne modifie ni
//! `api/src/appointments_*.rs` ni `api/src/scheduling.rs`. Le plan d'archi
//! d'origine prévoyait d'extraire la logique de création en un service
//! partagé — décision volontairement reportée : ce code est en production
//! (garde tutelle, idempotence, anti-double-booking) sur du trafic patient
//! réel, aucune CI n'est disponible ici pour vérifier un refactor, et personne
//! ne relira ce commit avant fusion éventuelle. On duplique donc le pattern
//! d'INSERT anti-double-booking (même table `appointment`, même contrainte
//! d'exclusion `appointment_no_overlap`) plutôt que de risquer un refactor de
//! code partagé non supervisé. **Un futur lot devra réconcilier ce chemin FHIR
//! avec les handlers existants** une fois qu'une revue humaine attentive sera
//! possible — ce module est un premier jet, pas l'architecture finale.
//!
//! ## Format d'erreur
//!
//! `interop::error::InteropError` (RFC 6749) reste réservé au token endpoint.
//! Ces routes exposent des ressources FHIR : leurs erreurs sont donc rendues
//! en `OperationOutcome` (R4), comme les lots siblings A2/A3.

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Extension, Json,
};
use core_tenancy::{with_tenant, TenancyError};
use integrations_interop::Scope;
use serde::Deserialize;
use serde_json::{json, Value};
use std::sync::Arc;
use uuid::Uuid;

use crate::{
    interop::auth::{require_scope, InteropClaims},
    AppState, InteropSigningKey, JobDispatcher,
};

// ─────────────────────────────────────────────────────────────────────────
// Erreur FHIR — OperationOutcome
// ─────────────────────────────────────────────────────────────────────────

/// Erreur du domaine FHIR Appointment, rendue en `OperationOutcome` R4.
///
/// Règle de choix 404 vs 422 (le sujet demande explicitement l'un ou
/// l'autre) : `404` quand c'est la ressource *adressée par l'URL* qui manque
/// (`GET`/`PATCH .../:id`) ; `422` quand c'est une ressource *référencée dans
/// le body* (patient/practitioner du POST) qui ne résout pas — la requête
/// elle-même est syntaxiquement valide, c'est son contenu qui échoue une
/// règle métier.
#[derive(Debug)]
pub enum FhirError {
    NotFound(String),
    Unprocessable(String),
    Conflict(String),
    BadRequest(String),
    Forbidden,
    Internal,
}

impl FhirError {
    fn not_found(msg: impl Into<String>) -> Self {
        Self::NotFound(msg.into())
    }
    fn unprocessable(msg: impl Into<String>) -> Self {
        Self::Unprocessable(msg.into())
    }
    fn conflict(msg: impl Into<String>) -> Self {
        Self::Conflict(msg.into())
    }
    fn bad_request(msg: impl Into<String>) -> Self {
        Self::BadRequest(msg.into())
    }
}

impl IntoResponse for FhirError {
    fn into_response(self) -> Response {
        let (status, code, diagnostics): (StatusCode, &str, String) = match self {
            FhirError::NotFound(m) => (StatusCode::NOT_FOUND, "not-found", m),
            FhirError::Unprocessable(m) => (StatusCode::UNPROCESSABLE_ENTITY, "business-rule", m),
            FhirError::Conflict(m) => (StatusCode::CONFLICT, "conflict", m),
            FhirError::BadRequest(m) => (StatusCode::BAD_REQUEST, "invalid", m),
            FhirError::Forbidden => (
                StatusCode::FORBIDDEN,
                "forbidden",
                "scope insuffisant".to_string(),
            ),
            FhirError::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "exception",
                "erreur interne".to_string(),
            ),
        };
        let body = json!({
            "resourceType": "OperationOutcome",
            "issue": [{
                "severity": "error",
                "code": code,
                "diagnostics": diagnostics,
            }]
        });
        (status, Json(body)).into_response()
    }
}

/// Toute erreur de transaction tenant (`with_tenant`) est traitée fail-closed :
/// jamais de détail DB exposé au partenaire.
fn internal_from_tenancy(_: TenancyError) -> FhirError {
    FhirError::Internal
}

// ─────────────────────────────────────────────────────────────────────────
// Détection de la violation d'exclusion anti-double-booking (23P01)
// ─────────────────────────────────────────────────────────────────────────

/// Détecte la violation de la contrainte d'exclusion `appointment_no_overlap`
/// (SQLSTATE `23P01`, Postgres `exclusion_violation`).
///
/// Copie volontaire de `appointments_response::is_exclusion_violation` — pas d'import
/// d'une fonction privée d'un autre module (cf. commentaire de module
/// ci-dessus sur la duplication assumée).
fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23P01")
    )
}

// ─────────────────────────────────────────────────────────────────────────
// Mapping de statut interne <-> FHIR R4 Appointment.status
// ─────────────────────────────────────────────────────────────────────────

/// Mappe `appointment.status` (interne) vers `Appointment.status` (FHIR R4,
/// valueset http://hl7.org/fhir/appointmentstatus). Choix documentés :
///
/// - `requested` → `pending` : le créneau est déjà réservé côté Nubia (pas une
///   simple intention — `proposed` signifie qu'aucun participant n'a encore
///   rien accepté), mais reste en attente de confirmation cabinet. `pending`
///   ("some or all participants have not finalized acceptance") colle mieux.
/// - `confirmed` → `booked`.
/// - `checked_in` → `checked-in` (valeur R4 dédiée).
/// - `in_progress` → `arrived` : R4 n'a pas de valeur "consultation en cours"
///   dédiée (ajoutée seulement en R5 sous `in-progress`) ; `arrived` (le
///   patient est présent et pris en charge) est la valeur R4 la plus proche.
/// - `done` → `fulfilled`.
/// - `cancelled` → `cancelled`.
/// - `no_show` → `noshow`.
fn internal_status_to_fhir(status: &str) -> &'static str {
    match status {
        "requested" => "pending",
        "confirmed" => "booked",
        "checked_in" => "checked-in",
        "in_progress" => "arrived",
        "done" => "fulfilled",
        "cancelled" => "cancelled",
        "no_show" => "noshow",
        _ => "entered-in-error",
    }
}

/// Mapping inverse, utilisé par le `PATCH` (mise à jour de statut). Seules les
/// valeurs FHIR que nous émettons nous-mêmes (cf. [`internal_status_to_fhir`])
/// sont acceptées en entrée — `proposed`/`waitlist`/`entered-in-error`/... ne
/// correspondent à aucun statut interne et sont rejetées (`400 invalid`)
/// plutôt que mappées approximativement.
fn fhir_status_to_internal(status: &str) -> Option<&'static str> {
    match status {
        "pending" => Some("requested"),
        "booked" => Some("confirmed"),
        "checked-in" => Some("checked_in"),
        "arrived" => Some("in_progress"),
        "fulfilled" => Some("done"),
        "cancelled" => Some("cancelled"),
        "noshow" => Some("no_show"),
        _ => None,
    }
}

/// Transitions de statut interne légales pour le `PATCH` (première tranche :
/// mise à jour de statut uniquement, pas de resource replace complet).
/// `done`/`cancelled`/`no_show` sont terminaux : aucune transition sortante
/// n'est autorisée (ex. `done` → `requested` est explicitement rejeté).
fn is_legal_transition(current: &str, target: &str) -> bool {
    matches!(
        (current, target),
        ("requested", "confirmed")
            | ("requested", "cancelled")
            | ("confirmed", "checked_in")
            | ("confirmed", "cancelled")
            | ("confirmed", "no_show")
            | ("checked_in", "in_progress")
            | ("checked_in", "cancelled")
            | ("in_progress", "done")
            | ("in_progress", "cancelled")
    )
}

// ─────────────────────────────────────────────────────────────────────────
// Représentation JSON FHIR minimale
// ─────────────────────────────────────────────────────────────────────────

#[derive(Debug, sqlx::FromRow)]
pub(crate) struct AppointmentRow {
    pub(crate) id: Uuid,
    pub(crate) patient_id: Uuid,
    pub(crate) practitioner_id: Uuid,
    pub(crate) starts_at: chrono::DateTime<chrono::Utc>,
    pub(crate) ends_at: chrono::DateTime<chrono::Utc>,
    pub(crate) status: String,
}

fn appointment_to_fhir(row: &AppointmentRow) -> Value {
    json!({
        "resourceType": "Appointment",
        "id": row.id,
        "status": internal_status_to_fhir(&row.status),
        "start": row.starts_at.to_rfc3339(),
        "end": row.ends_at.to_rfc3339(),
        "participant": [
            {
                "actor": { "reference": format!("Patient/{}", row.patient_id) },
                "status": "accepted"
            },
            {
                "actor": { "reference": format!("Practitioner/{}", row.practitioner_id) },
                "status": "accepted"
            }
        ]
    })
}

/// Parse une référence FHIR de recherche (`patient=`/`practitioner=`),
/// tolérant `<uuid>` nu ou `<ResourceType>/<uuid>`.
fn parse_ref_query(raw: Option<&str>, prefix: &str) -> Result<Option<Uuid>, FhirError> {
    raw.map(|r| r.strip_prefix(prefix).unwrap_or(r))
        .map(Uuid::parse_str)
        .transpose()
        .map_err(|_| FhirError::bad_request(format!("référence invalide (attendu {prefix}<uuid>)")))
}

// ─────────────────────────────────────────────────────────────────────────
// GET /v1/interop/fhir/Appointment/:id
// ─────────────────────────────────────────────────────────────────────────

/// `GET /v1/interop/fhir/Appointment/:id` — lecture d'un RDV par UUID interne.
///
/// Scope `appointments:read` requis. Toujours filtré explicitement par
/// `cabinet_id` (issu du token, jamais du path) EN PLUS du contexte RLS posé
/// par `with_tenant` — défense en profondeur, ne repose pas sur la seule RLS.
pub async fn get_appointment(
    State(state): State<AppState>,
    claims: InteropClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::AppointmentsRead).map_err(|_| FhirError::Forbidden)?;

    let cabinet_id = claims.cabinet_id;
    let row: Option<AppointmentRow> =
        with_tenant(&state.db, cabinet_id, move |mut tx| async move {
            let row = sqlx::query_as::<_, AppointmentRow>(
                "SELECT id, patient_id, practitioner_id, starts_at, ends_at, status \
             FROM appointment WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
            )
            .bind(id)
            .bind(cabinet_id)
            .fetch_optional(&mut *tx)
            .await?;
            Ok(row)
        })
        .await
        .map_err(internal_from_tenancy)?;

    let row = row.ok_or_else(|| FhirError::not_found("Appointment introuvable pour ce cabinet"))?;
    Ok(Json(appointment_to_fhir(&row)))
}

// ─────────────────────────────────────────────────────────────────────────
// GET /v1/interop/fhir/Appointment (search)
// ─────────────────────────────────────────────────────────────────────────

/// Query params de la recherche. Simplification pragmatique du paramètre
/// `date` FHIR (qui admet des préfixes `ge`/`le` et des valeurs répétées, mal
/// supportés par le désérialiseur `Query` d'axum/serde_urlencoded) :
/// `date_from`/`date_to` en RFC3339, bornes inclusives sur `starts_at`.
#[derive(Debug, Deserialize)]
pub struct AppointmentSearchQuery {
    pub patient: Option<String>,
    pub practitioner: Option<String>,
    pub date_from: Option<String>,
    pub date_to: Option<String>,
}

/// `GET /v1/interop/fhir/Appointment` — recherche scopée au cabinet du token.
///
/// Scope `appointments:read` requis. Filtres : `patient=`, `practitioner=`
/// (UUID nu ou `ResourceType/uuid`), `date_from=`/`date_to=` (RFC3339).
/// Retourne un `Bundle` FHIR de type `searchset`, limité à 200 résultats.
pub async fn search_appointments(
    State(state): State<AppState>,
    claims: InteropClaims,
    Query(query): Query<AppointmentSearchQuery>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::AppointmentsRead).map_err(|_| FhirError::Forbidden)?;

    let patient_id = parse_ref_query(query.patient.as_deref(), "Patient/")?;
    let practitioner_id = parse_ref_query(query.practitioner.as_deref(), "Practitioner/")?;
    let date_from = query
        .date_from
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| FhirError::bad_request("date_from invalide (RFC3339 attendu)"))?;
    let date_to = query
        .date_to
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| FhirError::bad_request("date_to invalide (RFC3339 attendu)"))?;

    let cabinet_id = claims.cabinet_id;
    let rows: Vec<AppointmentRow> = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let mut qb = sqlx::QueryBuilder::<sqlx::Postgres>::new(
            "SELECT id, patient_id, practitioner_id, starts_at, ends_at, status \
             FROM appointment WHERE cabinet_id = ",
        );
        qb.push_bind(cabinet_id);
        qb.push(" AND deleted_at IS NULL");
        if let Some(pid) = patient_id {
            qb.push(" AND patient_id = ").push_bind(pid);
        }
        if let Some(prid) = practitioner_id {
            qb.push(" AND practitioner_id = ").push_bind(prid);
        }
        if let Some(from) = date_from {
            qb.push(" AND starts_at >= ").push_bind(from);
        }
        if let Some(to) = date_to {
            qb.push(" AND starts_at <= ").push_bind(to);
        }
        qb.push(" ORDER BY starts_at ASC LIMIT 200");

        let rows = qb
            .build_query_as::<AppointmentRow>()
            .fetch_all(&mut *tx)
            .await?;
        Ok(rows)
    })
    .await
    .map_err(internal_from_tenancy)?;

    let entries: Vec<Value> = rows
        .iter()
        .map(|r| json!({ "resource": appointment_to_fhir(r) }))
        .collect();

    Ok(Json(json!({
        "resourceType": "Bundle",
        "type": "searchset",
        "total": entries.len(),
        "entry": entries,
    })))
}

// ─────────────────────────────────────────────────────────────────────────
// POST /v1/interop/fhir/Appointment
// ─────────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct FhirReference {
    pub reference: String,
}

#[derive(Debug, Deserialize)]
pub struct FhirParticipantIn {
    pub actor: FhirReference,
}

#[derive(Debug, Deserialize)]
pub struct FhirAppointmentIn {
    #[serde(default)]
    pub start: Option<String>,
    #[serde(default)]
    pub end: Option<String>,
    #[serde(default)]
    pub participant: Vec<FhirParticipantIn>,
}

/// Résout la référence FHIR d'un participant d'un type donné.
///
/// Exige le préfixe exact `"<ResourceType>/"` (pas de fallback UUID nu) :
/// un tableau `participant` mêlant Patient et Practitioner ne doit jamais
/// laisser un UUID ambigu être assigné au mauvais rôle.
fn extract_participant_ref(
    participants: &[FhirParticipantIn],
    resource_type: &str,
) -> Option<Uuid> {
    let prefix = format!("{resource_type}/");
    participants.iter().find_map(|p| {
        p.actor
            .reference
            .strip_prefix(&prefix)
            .and_then(|raw| Uuid::parse_str(raw).ok())
    })
}

// ─────────────────────────────────────────────────────────────────────────
// Couche service — pure (pas d'Axum), réutilisable par le handler FHIR
// ci-dessous ET par le mapping SIU HL7v2 (lot B9, `api/src/hl7v2/siu.rs`).
// Introduite au moment de B9 : au lancement de A6, ce fichier était du code
// tout neuf, non encore mergé, donc dupliquer plutôt que refactorer était le
// choix prudent (cf. doc de module). A6 est maintenant mergé sur `main` et
// relu — l'extraire proprement ici, une fois, est plus sûr que de dupliquer
// une troisième fois la logique anti-double-booking/idempotence pour B9.
// ─────────────────────────────────────────────────────────────────────────

/// Entrée de [`create_appointment_service`] — indépendante du protocole
/// (FHIR REST ou HL7v2 SIU) qui l'appelle.
pub struct CreateAppointmentInput {
    pub patient_id: Uuid,
    pub practitioner_id: Uuid,
    pub starts_at: chrono::DateTime<chrono::Utc>,
    pub ends_at: chrono::DateTime<chrono::Utc>,
    /// Clé d'idempotence — `Idempotency-Key` HTTP côté FHIR, `MSH-10`
    /// (préfixé) côté HL7v2. Toujours requise : la dédup est portée par
    /// `appointment.idempotency_key`, pas par l'appelant.
    pub idempotency_key: String,
}

/// Erreur de [`create_appointment_service`] — traduite en `FhirError`
/// (OperationOutcome) côté FHIR, en NACK/AE côté HL7v2 (lot B9).
#[derive(Debug, PartialEq, Eq)]
pub enum CreateAppointmentError {
    PatientNotFound,
    PractitionerNotFound,
    IdempotencyConflict,
    SlotTaken,
    Internal,
}

/// Crée un rendez-vous pour un patient/praticien déjà existants dans ce
/// cabinet (pas de création/matching patient ici — lot A4). Statut initial
/// `confirmed` : un appelant externe (partenaire FHIR ou SIH via HL7v2)
/// affirme une réservation déjà actée, pas une demande à confirmer (contexte
/// différent du flux patient qui démarre à `requested`).
///
/// `actor_id`/`actor_role` alimentent `audit_log` — `actor_role` distingue
/// la provenance (`"interop_client"` FHIR vs `"hl7v2_partner"` HL7v2) sans
/// dupliquer cette fonction.
pub async fn create_appointment_service(
    db: &sqlx::PgPool,
    cabinet_id: Uuid,
    actor_id: Uuid,
    actor_role: &str,
    input: CreateAppointmentInput,
) -> Result<AppointmentRow, CreateAppointmentError> {
    let CreateAppointmentInput {
        patient_id,
        practitioner_id,
        starts_at,
        ends_at,
        idempotency_key,
    } = input;
    let actor_role = actor_role.to_string();

    let fingerprint = format!(
        "patient={patient_id}|practitioner={practitioner_id}|start={}|end={}",
        starts_at.to_rfc3339(),
        ends_at.to_rfc3339()
    );

    with_tenant(db, cabinet_id, move |mut tx| async move {
        // Le patient référencé doit exister et appartenir à ce cabinet
        // (pas de création/matching ici — lot A4).
        let patient_row = sqlx::query(
            "SELECT id FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .fetch_optional(&mut *tx)
        .await?;
        if patient_row.is_none() {
            return Ok(Err(CreateAppointmentError::PatientNotFound));
        }

        let practitioner_row =
            sqlx::query("SELECT id FROM practitioner WHERE id = $1 AND cabinet_id = $2")
                .bind(practitioner_id)
                .bind(cabinet_id)
                .fetch_optional(&mut *tx)
                .await?;
        if practitioner_row.is_none() {
            return Ok(Err(CreateAppointmentError::PractitionerNotFound));
        }

        // Idempotence — même convention que appointments.rs (#3632) : clé
        // rejouée avec une empreinte différente → conflit, jamais absorbée.
        let existing = sqlx::query_as::<_, (Uuid, Option<String>)>(
            "SELECT id, idempotency_fingerprint FROM appointment \
             WHERE cabinet_id = $1 AND idempotency_key = $2",
        )
        .bind(cabinet_id)
        .bind(&idempotency_key)
        .fetch_optional(&mut *tx)
        .await?;

        if let Some((existing_id, existing_fingerprint)) = existing {
            if existing_fingerprint.as_deref() != Some(fingerprint.as_str()) {
                return Ok(Err(CreateAppointmentError::IdempotencyConflict));
            }
            let row = sqlx::query_as::<_, AppointmentRow>(
                "SELECT id, patient_id, practitioner_id, starts_at, ends_at, status \
                 FROM appointment WHERE id = $1",
            )
            .bind(existing_id)
            .fetch_one(&mut *tx)
            .await?;
            tx.commit().await?;
            return Ok(Ok(row));
        }

        // INSERT — statut initial 'confirmed' (cf. doc de la fonction).
        // 23P01 (appointment_no_overlap) → SlotTaken.
        let insert_result = sqlx::query_as::<_, AppointmentRow>(
            "INSERT INTO appointment \
             (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, idempotency_key, idempotency_fingerprint) \
             VALUES ($1, $2, $3, $4, $5, 'confirmed', $6, $7) \
             RETURNING id, patient_id, practitioner_id, starts_at, ends_at, status",
        )
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(practitioner_id)
        .bind(starts_at)
        .bind(ends_at)
        .bind(&idempotency_key)
        .bind(&fingerprint)
        .fetch_one(&mut *tx)
        .await;

        let row = match insert_result {
            Ok(row) => row,
            Err(e) if is_exclusion_violation(&e) => {
                return Ok(Err(CreateAppointmentError::SlotTaken))
            }
            Err(e) => return Err(TenancyError::Db(e)),
        };

        sqlx::query(
            "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
             VALUES ($1, $2, $3, 'interop_appointment_created', 'appointment', $4)",
        )
        .bind(cabinet_id)
        .bind(actor_id)
        .bind(&actor_role)
        .bind(row.id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(Ok(row))
    })
    .await
    .map_err(|_| CreateAppointmentError::Internal)
    .and_then(|inner| inner)
}

impl From<CreateAppointmentError> for FhirError {
    fn from(err: CreateAppointmentError) -> Self {
        match err {
            CreateAppointmentError::PatientNotFound => {
                FhirError::unprocessable("patient référencé inconnu ou hors de ce cabinet")
            }
            CreateAppointmentError::PractitionerNotFound => {
                FhirError::unprocessable("practitioner référencé inconnu ou hors de ce cabinet")
            }
            CreateAppointmentError::IdempotencyConflict => {
                FhirError::conflict("Idempotency-Key rejouée avec une charge de requête différente")
            }
            CreateAppointmentError::SlotTaken => {
                FhirError::conflict("créneau déjà occupé pour ce praticien (chevauchement)")
            }
            CreateAppointmentError::Internal => FhirError::Internal,
        }
    }
}

/// `POST /v1/interop/fhir/Appointment` — création d'un RDV pour un patient et
/// un praticien EXISTANTS (référencés par UUID interne dans `participant`).
///
/// Scope `appointments:write` requis. `Idempotency-Key` **obligatoire** (à la
/// différence du flux patient où l'en-tête est optionnel) : un partenaire/SIH
/// rejoue ses requêtes, on ne veut jamais absorber une resoumission sans
/// protection anti-doublon explicite. Même convention que
/// `appointments_create::create_appointment` : la clé est comparée à une empreinte
/// (patient+practitioner+start+end) — clé rejouée avec une charge différente
/// → `409 conflict` plutôt qu'absorbée silencieusement.
///
/// Ne crée PAS le patient référencé s'il n'existe pas ou n'appartient pas à
/// ce cabinet (matching patient = lot A4, hors scope ici) → `422`.
///
/// Statut initial **`confirmed`** (et non `requested` comme le flux patient) :
/// un partenaire/SIH qui pousse un RDV via HL7/FHIR affirme une réservation
/// déjà actée côté SIH — il ne "demande" pas une confirmation cabinet, il la
/// notifie. Le cabinet reste libre de l'annuler ensuite (`PATCH` → `cancelled`).
///
/// Ce chemin n'associe pas de `availability_slot` (pas de logique de créneau
/// partagée avec le flux patient/secrétariat, cf. commentaire de module) : la
/// sécurité anti-double-booking repose entièrement sur la contrainte
/// d'exclusion DB `appointment_no_overlap` (`23P01` → `409 conflict`).
pub async fn create_appointment(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    Extension(InteropSigningKey(signing_key)): Extension<InteropSigningKey>,
    claims: InteropClaims,
    headers: HeaderMap,
    Json(body): Json<FhirAppointmentIn>,
) -> Result<(StatusCode, Json<Value>), FhirError> {
    require_scope(&claims, Scope::AppointmentsWrite).map_err(|_| FhirError::Forbidden)?;

    let idempotency_key = headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .ok_or_else(|| FhirError::bad_request("en-tête Idempotency-Key requis"))?;

    let start = body
        .start
        .as_deref()
        .ok_or_else(|| FhirError::bad_request("start requis"))?;
    let end = body
        .end
        .as_deref()
        .ok_or_else(|| FhirError::bad_request("end requis"))?;
    let starts_at: chrono::DateTime<chrono::Utc> = start
        .parse()
        .map_err(|_| FhirError::bad_request("start invalide (RFC3339 attendu)"))?;
    let ends_at: chrono::DateTime<chrono::Utc> = end
        .parse()
        .map_err(|_| FhirError::bad_request("end invalide (RFC3339 attendu)"))?;
    if ends_at <= starts_at {
        return Err(FhirError::bad_request("end doit être postérieur à start"));
    }

    let patient_id = extract_participant_ref(&body.participant, "Patient")
        .ok_or_else(|| FhirError::bad_request("participant Patient/<uuid> requis"))?;
    let practitioner_id = extract_participant_ref(&body.participant, "Practitioner")
        .ok_or_else(|| FhirError::bad_request("participant Practitioner/<uuid> requis"))?;

    let cabinet_id = claims.cabinet_id;
    let actor_id = claims.sub;

    let row = create_appointment_service(
        &state.db,
        cabinet_id,
        actor_id,
        "interop_client",
        CreateAppointmentInput {
            patient_id,
            practitioner_id,
            starts_at,
            ends_at,
            idempotency_key,
        },
    )
    .await?;

    tracing::info!(
        cabinet_id = %cabinet_id,
        client_id = %claims.client_id,
        appointment_id = %row.id,
        "interop appointment created"
    );

    crate::interop::subscription::dispatch_notification(
        &state,
        &dispatcher,
        &signing_key,
        cabinet_id,
        "Appointment",
        row.id,
    )
    .await;

    Ok((StatusCode::CREATED, Json(appointment_to_fhir(&row))))
}

// ─────────────────────────────────────────────────────────────────────────
// PATCH /v1/interop/fhir/Appointment/:id — mise à jour de statut
// ─────────────────────────────────────────────────────────────────────────

/// Corps du `PATCH` : uniquement le champ `status` (première tranche — pas de
/// resource replace complet). `PATCH` plutôt que `PUT` : sémantiquement, on ne
/// modifie qu'un seul champ d'une ressource existante, on ne la remplace pas
/// entièrement (un `PUT` laisserait entendre que `start`/`end`/`participant`
/// sont aussi mis à jour, ce qui n'est pas le cas dans cette première tranche).
#[derive(Debug, Deserialize)]
pub struct FhirAppointmentStatusPatch {
    pub status: String,
}

/// Erreur de [`update_appointment_status_service`].
#[derive(Debug, PartialEq, Eq)]
pub enum UpdateAppointmentStatusError {
    NotFound,
    IllegalTransition { from: String, to: String },
    Internal,
}

/// Met à jour le statut d'un rendez-vous existant (transition validée par
/// [`is_legal_transition`]) — service pur, réutilisé par le handler FHIR
/// ci-dessous et par le mapping SIU^S15 (annulation, lot B9,
/// `api/src/hl7v2/siu.rs`). Voir la doc de [`create_appointment_service`]
/// pour le contexte de cette extraction.
pub async fn update_appointment_status_service(
    db: &sqlx::PgPool,
    cabinet_id: Uuid,
    appointment_id: Uuid,
    target_status: &str,
) -> Result<AppointmentRow, UpdateAppointmentStatusError> {
    let target_status = target_status.to_string();
    with_tenant(db, cabinet_id, move |mut tx| async move {
        let current = sqlx::query_as::<_, AppointmentRow>(
            "SELECT id, patient_id, practitioner_id, starts_at, ends_at, status \
             FROM appointment WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
        )
        .bind(appointment_id)
        .bind(cabinet_id)
        .fetch_optional(&mut *tx)
        .await?;

        let Some(current) = current else {
            return Ok(Err(UpdateAppointmentStatusError::NotFound));
        };

        if !is_legal_transition(&current.status, &target_status) {
            return Ok(Err(UpdateAppointmentStatusError::IllegalTransition {
                from: current.status.clone(),
                to: target_status.clone(),
            }));
        }

        let updated = sqlx::query_as::<_, AppointmentRow>(
            "UPDATE appointment SET status = $1, updated_at = now() \
             WHERE id = $2 AND cabinet_id = $3 \
             RETURNING id, patient_id, practitioner_id, starts_at, ends_at, status",
        )
        .bind(&target_status)
        .bind(appointment_id)
        .bind(cabinet_id)
        .fetch_one(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(Ok(updated))
    })
    .await
    .map_err(|_| UpdateAppointmentStatusError::Internal)
    .and_then(|inner| inner)
}

impl From<UpdateAppointmentStatusError> for FhirError {
    fn from(err: UpdateAppointmentStatusError) -> Self {
        match err {
            UpdateAppointmentStatusError::NotFound => {
                FhirError::not_found("Appointment introuvable pour ce cabinet")
            }
            UpdateAppointmentStatusError::IllegalTransition { from, to } => {
                FhirError::unprocessable(format!(
                    "transition de statut '{from}' -> '{to}' non autorisée"
                ))
            }
            UpdateAppointmentStatusError::Internal => FhirError::Internal,
        }
    }
}

/// `PATCH /v1/interop/fhir/Appointment/:id` — transition de statut.
///
/// Scope `appointments:write` requis. Scopé `cabinet_id` (404 si le RDV
/// n'existe pas ou appartient à un autre cabinet). Valide que la transition
/// est légale (cf. [`is_legal_transition`]) — ex. `done` → `requested` est
/// rejeté (`422 business-rule`), pas silencieusement accepté.
pub async fn update_appointment_status(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    Extension(InteropSigningKey(signing_key)): Extension<InteropSigningKey>,
    claims: InteropClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<FhirAppointmentStatusPatch>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::AppointmentsWrite).map_err(|_| FhirError::Forbidden)?;

    let target_status = fhir_status_to_internal(&body.status)
        .ok_or_else(|| FhirError::bad_request("status FHIR non supporté"))?;

    let cabinet_id = claims.cabinet_id;
    let row = update_appointment_status_service(&state.db, cabinet_id, id, target_status).await?;

    // Pas de `tracing::info!` préexistant dans ce handler (contrairement à
    // `create_appointment`) — l'appel est ajouté au même endroit logique :
    // juste après la transaction commitée, avant la réponse.
    crate::interop::subscription::dispatch_notification(
        &state,
        &dispatcher,
        &signing_key,
        cabinet_id,
        "Appointment",
        row.id,
    )
    .await;

    Ok(Json(appointment_to_fhir(&row)))
}

// ─────────────────────────────────────────────────────────────────────────
// Tests unitaires purs (pas de DB requise)
// ─────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use std::fmt;

    // ── is_exclusion_violation : détection 23P01 sans DB réelle ─────────────

    #[derive(Debug)]
    struct FakeDbError {
        code: Option<String>,
    }

    impl fmt::Display for FakeDbError {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            write!(f, "fake db error")
        }
    }

    impl std::error::Error for FakeDbError {}

    impl sqlx::error::DatabaseError for FakeDbError {
        fn message(&self) -> &str {
            "fake"
        }
        fn code(&self) -> Option<std::borrow::Cow<'_, str>> {
            self.code.as_deref().map(std::borrow::Cow::Borrowed)
        }
        fn as_error(&self) -> &(dyn std::error::Error + Send + Sync + 'static) {
            self
        }
        fn as_error_mut(&mut self) -> &mut (dyn std::error::Error + Send + Sync + 'static) {
            self
        }
        fn into_error(self: Box<Self>) -> Box<dyn std::error::Error + Send + Sync + 'static> {
            self
        }
        fn kind(&self) -> sqlx::error::ErrorKind {
            match self.code.as_deref() {
                Some("23P01") => sqlx::error::ErrorKind::Other,
                Some("23505") => sqlx::error::ErrorKind::UniqueViolation,
                Some("23514") => sqlx::error::ErrorKind::CheckViolation,
                _ => sqlx::error::ErrorKind::Other,
            }
        }
    }

    fn db_error(code: &str) -> sqlx::Error {
        sqlx::Error::Database(Box::new(FakeDbError {
            code: Some(code.to_string()),
        }))
    }

    #[test]
    fn detects_exclusion_violation_23p01() {
        assert!(is_exclusion_violation(&db_error("23P01")));
    }

    #[test]
    fn ignores_unrelated_error_codes() {
        assert!(!is_exclusion_violation(&db_error("23505"))); // unique_violation
        assert!(!is_exclusion_violation(&db_error("23514"))); // check_violation
    }

    #[test]
    fn ignores_non_database_errors() {
        assert!(!is_exclusion_violation(&sqlx::Error::RowNotFound));
    }

    // ── Mapping de statut interne <-> FHIR ───────────────────────────────────

    #[test]
    fn internal_status_to_fhir_matches_documented_mapping() {
        assert_eq!(internal_status_to_fhir("requested"), "pending");
        assert_eq!(internal_status_to_fhir("confirmed"), "booked");
        assert_eq!(internal_status_to_fhir("checked_in"), "checked-in");
        assert_eq!(internal_status_to_fhir("in_progress"), "arrived");
        assert_eq!(internal_status_to_fhir("done"), "fulfilled");
        assert_eq!(internal_status_to_fhir("cancelled"), "cancelled");
        assert_eq!(internal_status_to_fhir("no_show"), "noshow");
    }

    #[test]
    fn fhir_status_to_internal_is_the_exact_inverse() {
        for internal in [
            "requested",
            "confirmed",
            "checked_in",
            "in_progress",
            "done",
            "cancelled",
            "no_show",
        ] {
            let fhir = internal_status_to_fhir(internal);
            assert_eq!(fhir_status_to_internal(fhir), Some(internal));
        }
    }

    #[test]
    fn fhir_status_to_internal_rejects_unknown_values() {
        assert_eq!(fhir_status_to_internal("proposed"), None);
        assert_eq!(fhir_status_to_internal("waitlist"), None);
        assert_eq!(fhir_status_to_internal("entered-in-error"), None);
        assert_eq!(fhir_status_to_internal("bogus"), None);
    }

    // ── Transitions de statut ────────────────────────────────────────────────

    #[test]
    fn legal_transitions_are_accepted() {
        assert!(is_legal_transition("requested", "confirmed"));
        assert!(is_legal_transition("requested", "cancelled"));
        assert!(is_legal_transition("confirmed", "checked_in"));
        assert!(is_legal_transition("confirmed", "cancelled"));
        assert!(is_legal_transition("confirmed", "no_show"));
        assert!(is_legal_transition("checked_in", "in_progress"));
        assert!(is_legal_transition("checked_in", "cancelled"));
        assert!(is_legal_transition("in_progress", "done"));
        assert!(is_legal_transition("in_progress", "cancelled"));
    }

    #[test]
    fn terminal_states_reject_any_outgoing_transition() {
        for target in [
            "requested",
            "confirmed",
            "checked_in",
            "in_progress",
            "done",
            "cancelled",
            "no_show",
        ] {
            assert!(
                !is_legal_transition("done", target),
                "done -> {target} should be illegal"
            );
            assert!(
                !is_legal_transition("cancelled", target),
                "cancelled -> {target} should be illegal"
            );
            assert!(
                !is_legal_transition("no_show", target),
                "no_show -> {target} should be illegal"
            );
        }
    }

    #[test]
    fn illegal_backward_transition_is_rejected() {
        assert!(!is_legal_transition("done", "requested"));
        assert!(!is_legal_transition("confirmed", "requested"));
        assert!(!is_legal_transition("checked_in", "requested"));
    }

    #[test]
    fn same_state_transition_is_not_in_the_legal_matrix() {
        assert!(!is_legal_transition("requested", "requested"));
        assert!(!is_legal_transition("confirmed", "confirmed"));
    }

    // ── Extraction de références FHIR ────────────────────────────────────────

    fn participant(reference: &str) -> FhirParticipantIn {
        FhirParticipantIn {
            actor: FhirReference {
                reference: reference.to_string(),
            },
        }
    }

    #[test]
    fn extracts_patient_and_practitioner_references() {
        let patient_id = Uuid::new_v4();
        let practitioner_id = Uuid::new_v4();
        let participants = vec![
            participant(&format!("Patient/{patient_id}")),
            participant(&format!("Practitioner/{practitioner_id}")),
        ];
        assert_eq!(
            extract_participant_ref(&participants, "Patient"),
            Some(patient_id)
        );
        assert_eq!(
            extract_participant_ref(&participants, "Practitioner"),
            Some(practitioner_id)
        );
    }

    #[test]
    fn rejects_bare_uuid_without_resource_type_prefix() {
        let participants = vec![participant(&Uuid::new_v4().to_string())];
        assert_eq!(extract_participant_ref(&participants, "Patient"), None);
    }

    #[test]
    fn does_not_confuse_participant_types() {
        let practitioner_id = Uuid::new_v4();
        let participants = vec![participant(&format!("Practitioner/{practitioner_id}"))];
        assert_eq!(extract_participant_ref(&participants, "Patient"), None);
    }

    #[test]
    fn parse_ref_query_accepts_bare_uuid_and_prefixed_form() {
        let id = Uuid::new_v4();
        assert_eq!(
            parse_ref_query(Some(&id.to_string()), "Patient/").unwrap(),
            Some(id)
        );
        assert_eq!(
            parse_ref_query(Some(&format!("Patient/{id}")), "Patient/").unwrap(),
            Some(id)
        );
        assert_eq!(parse_ref_query(None, "Patient/").unwrap(), None);
    }

    #[test]
    fn parse_ref_query_rejects_malformed_uuid() {
        assert!(parse_ref_query(Some("not-a-uuid"), "Patient/").is_err());
    }
}
