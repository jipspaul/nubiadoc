//! Handlers de lecture patient de base sur un RDV — liste paginée
//! (`list_appointments`) et détail (`get_appointment`) — extrait de
//! `appointments.rs` (refactor pur, aucun changement de comportement,
//! issue #4329) : `appointments.rs` dépassait largement le plafond absolu
//! de 700 lignes fixé par CLAUDE.md.
//!
//! Les lectures enrichies (préparation, directions, file d'attente) vivent
//! dans `appointments_preparation.rs` et `appointments_read_extras.rs`
//! (séparées uniquement pour rester sous le plafond de taille — regrouper
//! les 5 lectures dans un seul fichier comme suggéré par l'issue aurait
//! produit ~965 lignes, très au-delà du plafond absolu). Les structs de
//! réponse partagées (`AppointmentDetail`, `ProviderDetail`, `CabinetInfo`)
//! et le helper `fetch_cabinet_for_response` vivent dans
//! `appointments_response.rs`.

use axum::{
    extract::{Path, Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    appointments_response::{
        fetch_beneficiary_for_response, fetch_cabinet_for_response, format_establishment_address,
        AppointmentDetail, BeneficiarySummary, CabinetInfo, ProviderDetail,
    },
    auth::{AppError, PatientAccountClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct AppointmentsQuery {
    /// Filtre par statut (`upcoming` | `past`). Alias pour rétro-compatibilité front.
    pub status: Option<String>,
    /// Alias `filter=upcoming|history` (convention Flutter nubia_data). `history` → `past`.
    pub filter: Option<String>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct ProviderSummary {
    pub display_name: Option<String>,
    /// #3825 : absente jusqu'ici — le front affiche « <motif> · <spécialité> »,
    /// séparateur toujours pendant faute de donnée côté liste (le détail,
    /// lui, l'exposait déjà via `ProviderDetail::specialty`).
    pub specialty: Option<String>,
}

#[derive(Serialize)]
pub struct AppointmentItem {
    pub id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub status: String,
    pub motif: Option<String>,
    pub provider: ProviderSummary,
    /// #5563 : bénéficiaire du RDV (soi-même vs quel dépendant) — jusqu'ici
    /// absent, rendant un RDV de dépendant indiscernable des RDV du tuteur.
    pub beneficiary: BeneficiarySummary,
    /// #3845 : restitue la demande de rappel (colonne persistée, jusqu'ici
    /// write-only côté patient — le POST confirmait l'enregistrement mais
    /// aucune lecture ne le montrait, rendant la demande invisible au
    /// rafraîchissement).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub callback_requested_at: Option<String>,
    /// #6130 : jusqu'ici absent de la liste (contrairement au détail), ce qui
    /// laissait le bouton "Itinéraire" de la carte héros accueil toujours
    /// désactivé (`cabinetAddress` systématiquement `null` côté front).
    pub cabinet: CabinetInfo,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct AppointmentsResponse {
    pub data: Vec<AppointmentItem>,
    pub page: PageInfo,
}

fn encode_cursor(starts_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", starts_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/appointments` — liste paginée des RDV du patient connecté, tous praticiens.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (policy 0029).
/// `provider.display_name` n'est visible que si `is_listed = true` (policy 0011) ;
/// retourné `null` sinon — comportement attendu en MVP.
pub async fn list_appointments(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<AppointmentsQuery>,
) -> Result<Json<AppointmentsResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);

    // `filter` est l'alias Flutter (history → past). `status` garde la rétro-compat.
    let effective_status = params
        .filter
        .as_deref()
        .map(|f| if f == "history" { "past" } else { f })
        .or(params.status.as_deref());

    let is_past = effective_status == Some("past");

    // Statuts réels d'appointment (hors vues upcoming/past) — whitelist fermée,
    // seule interpolée directement dans le SQL (pas d'entrée libre possible).
    const REAL_STATUSES: &[&str] = &[
        "requested",
        "confirmed",
        "checked_in",
        "in_progress",
        "done",
        "cancelled",
        "no_show",
    ];

    let status_clause: String = match effective_status {
        // #4340 : checked_in/in_progress est borné au jour courant, meme
        // garde que get_appointment_queue (:1556) et get_waiting_room
        // (scheduling.rs:526) - sans elle, un RDV in_progress jamais cloture
        // reste "a venir" indefiniment, alors que queue/waiting-room l'ont
        // deja exclu (incoherence cross-vue).
        // Fenêtre GLISSANTE (now ± 1 jour), PAS `date_trunc('day', now())` :
        // meme correctif qu'ailleurs (#4869, scheduling.rs:339) - un RDV
        // checked_in juste avant minuit doit rester upcoming apres minuit (#3777).
        Some("upcoming") => " AND ((a.status IN ('checked_in','in_progress') \
              AND a.starts_at >= now() - interval '1 day' \
              AND a.starts_at < now() + interval '1 day') \
              OR (a.starts_at > now() AND a.status IN ('requested','confirmed')))"
            .to_string(),
        Some("past") => " AND (a.status IN ('done','cancelled','no_show') \
              OR (a.starts_at <= now() AND a.status IN ('requested','confirmed')))"
            .to_string(),
        Some(s) if REAL_STATUSES.contains(&s) => format!(" AND a.status = '{s}'"),
        // `status` nommé mais non reconnu (ni vue upcoming/past, ni vrai statut) :
        // avant, tombait silencieusement dans une clause vide (#3877) → renvoyait
        // TOUS les RDV au lieu de filtrer. Un filtre nommé doit filtrer ou être refusé.
        Some(_) => return Err(AppError::ValidationError),
        None => String::new(),
    };

    let order = if is_past { "DESC" } else { "ASC" };

    let cursor = match params.cursor.as_deref() {
        Some(s) => Some(decode_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };

    // $1 = fetch_limit ; si cursor : $2 = starts_at, $3 = id
    let cursor_clause = if cursor.is_some() {
        if is_past {
            " AND (a.starts_at < $2 OR (a.starts_at = $2 AND a.id < $3))"
        } else {
            " AND (a.starts_at > $2 OR (a.starts_at = $2 AND a.id > $3))"
        }
    } else {
        ""
    };

    let sql = format!(
        "SELECT \
             a.id, a.starts_at, a.ends_at, a.status, a.motif, a.callback_requested_at, \
             pt.patient_account_id AS beneficiary_account_id, \
             pt.first_name AS beneficiary_first_name, \
             pt.last_name AS beneficiary_last_name, \
             (SELECT p.display_name FROM provider p \
              WHERE p.practitioner_id = a.practitioner_id LIMIT 1) \
              AS provider_display_name, \
             (SELECT p.specialite FROM provider p \
              WHERE p.practitioner_id = a.practitioner_id LIMIT 1) \
              AS provider_specialty, \
             c.raison_sociale AS cabinet_name, \
             c.settings->>'address' AS cabinet_address, \
             (SELECT e.address FROM provider p \
              LEFT JOIN establishment e ON e.id = p.establishment_id \
              WHERE p.practitioner_id = a.practitioner_id LIMIT 1) \
              AS establishment_address \
         FROM appointment a \
         LEFT JOIN patient pt ON pt.id = a.patient_id \
         LEFT JOIN cabinet c ON c.id = a.cabinet_id \
         WHERE a.deleted_at IS NULL \
         {status_clause}{cursor_clause} \
         ORDER BY a.starts_at {order}, a.id {order} \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Cf. cancel_appointment : requis pour la branche tutelle de
    // appointment_patient_read (migration 0196, account_guardianship RLS).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let fetch_limit = limit + 1;

    let rows = match cursor {
        Some((cursor_starts_at, cursor_id)) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_starts_at)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        None => sqlx::query(&sql)
            .bind(fetch_limit)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<AppointmentItem> = Vec::with_capacity(visible.len());
    let mut last_starts_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        let ends_at: chrono::DateTime<chrono::Utc> =
            row.try_get("ends_at").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let motif: Option<String> = row.try_get("motif").map_err(|_| AppError::Internal)?;
        let display_name: Option<String> = row
            .try_get("provider_display_name")
            .map_err(|_| AppError::Internal)?;
        let specialty: Option<String> = row
            .try_get("provider_specialty")
            .map_err(|_| AppError::Internal)?;
        let callback_requested_at: Option<chrono::DateTime<chrono::Utc>> = row
            .try_get("callback_requested_at")
            .map_err(|_| AppError::Internal)?;
        let beneficiary_account_id: Option<Uuid> = row
            .try_get("beneficiary_account_id")
            .map_err(|_| AppError::Internal)?;
        let beneficiary_first_name: Option<String> = row
            .try_get("beneficiary_first_name")
            .map_err(|_| AppError::Internal)?;
        let beneficiary_last_name: Option<String> = row
            .try_get("beneficiary_last_name")
            .map_err(|_| AppError::Internal)?;
        let is_self = beneficiary_account_id == Some(claims.account_id);
        let cabinet_name: Option<String> = row
            .try_get("cabinet_name")
            .map_err(|_| AppError::Internal)?;
        let cabinet_address: Option<String> = row
            .try_get("cabinet_address")
            .map_err(|_| AppError::Internal)?;
        let establishment_address: Option<serde_json::Value> = row
            .try_get("establishment_address")
            .map_err(|_| AppError::Internal)?;
        // Même repli que `fetch_cabinet_for_response` (#3557) : `cabinet.settings`
        // ne porte pas toujours d'adresse, on retombe alors sur l'annuaire.
        let cabinet_address = cabinet_address.or_else(|| {
            establishment_address
                .as_ref()
                .and_then(format_establishment_address)
        });

        last_starts_at = Some(starts_at);
        last_id = Some(id);

        data.push(AppointmentItem {
            id,
            starts_at: starts_at.to_rfc3339(),
            ends_at: ends_at.to_rfc3339(),
            status,
            motif,
            provider: ProviderSummary {
                display_name,
                specialty,
            },
            cabinet: CabinetInfo {
                name: cabinet_name.unwrap_or_default(),
                address: cabinet_address,
            },
            beneficiary: BeneficiarySummary {
                account_id: beneficiary_account_id,
                is_self,
                first_name: if is_self {
                    None
                } else {
                    beneficiary_first_name
                },
                last_name: if is_self { None } else { beneficiary_last_name },
            },
            callback_requested_at: callback_requested_at.map(|dt| dt.to_rfc3339()),
        });
    }

    let next_cursor = if has_more {
        last_starts_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        account_id = %claims.account_id,
        count = data.len(),
        has_more,
        "appointments listed"
    );

    Ok(Json(AppointmentsResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

/// `GET /v1/appointments/:id` — détail d'un RDV du patient connecté.
///
/// Token `kind:"patient"` requis. Ownership vérifié par RLS (policy 0029) :
/// si le RDV n'appartient pas au patient ou n'existe pas → `404` (anti-énumération).
/// Après fetch, le GUC `app.current_cabinet_id` est positionné pour lire le cabinet
/// et écrire l'entrée d'audit (§07 §2.9).
pub async fn get_appointment(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<AppointmentDetail>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient pour appointment_patient_read (policy 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Cf. cancel_appointment : requis pour la branche tutelle de
    // appointment_patient_read (migration 0196, account_guardianship RLS).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch appointment — RLS garantit l'ownership (404 si autre patient ou inexistant).
    let row = sqlx::query(
        "SELECT id, starts_at, ends_at, status, motif, cabinet_id, practitioner_id, \
                patient_id, callback_requested_at \
         FROM appointment \
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let starts_at: chrono::DateTime<chrono::Utc> =
        row.try_get("starts_at").map_err(|_| AppError::Internal)?;
    let ends_at: chrono::DateTime<chrono::Utc> =
        row.try_get("ends_at").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let motif: Option<String> = row.try_get("motif").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
    let callback_requested_at: Option<chrono::DateTime<chrono::Utc>> = row
        .try_get("callback_requested_at")
        .map_err(|_| AppError::Internal)?;

    // Scope cabinet pour provider_cabinet_manage + tenant_isolation (cabinet) + audit_log.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch provider (inclut les non-listés via provider_cabinet_manage).
    let provider_row = sqlx::query(
        "SELECT id, display_name, specialite FROM provider \
         WHERE practitioner_id = $1 \
         LIMIT 1",
    )
    .bind(practitioner_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (provider_id, provider_display_name, provider_specialty) = match provider_row {
        Some(r) => {
            let pid: Uuid = r.try_get("id").map_err(|_| AppError::Internal)?;
            let dn: String = r.try_get("display_name").map_err(|_| AppError::Internal)?;
            let sp: Option<String> = r.try_get("specialite").map_err(|_| AppError::Internal)?;
            (Some(pid), Some(dn), sp)
        }
        None => (None, None, None),
    };

    // Fetch cabinet (accessible via tenant_isolation après SET LOCAL cabinet GUC) +
    // fallback establishment (#3799, même helper que create/patch_appointment).
    let (cabinet_name, cabinet_address) =
        fetch_cabinet_for_response(&mut tx, cabinet_id, practitioner_id).await?;

    // Bénéficiaire (#5563) : soi-même vs quel dépendant.
    let beneficiary =
        fetch_beneficiary_for_response(&mut tx, patient_id, claims.account_id).await?;

    // Audit (§07 §2.9) — cabinet_id correspond au GUC positionné ci-dessus.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'read_appointment', 'appointment', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        "appointment detail queried"
    );

    Ok(Json(AppointmentDetail {
        id,
        starts_at: starts_at.to_rfc3339(),
        ends_at: ends_at.to_rfc3339(),
        status,
        motif,
        provider: ProviderDetail {
            id: provider_id,
            display_name: provider_display_name,
            specialty: provider_specialty,
        },
        cabinet: CabinetInfo {
            name: cabinet_name,
            address: cabinet_address,
        },
        beneficiary,
        callback_requested_at: callback_requested_at.map(|dt| dt.to_rfc3339()),
    }))
}
