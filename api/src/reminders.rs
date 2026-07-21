//! Handler `GET /v1/reminders` — rappels de suivi et prévention patient.

use axum::extract::State;
use axum::Json;
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

/// Un rappel patient (RDV, document à signer, prévention).
#[derive(Serialize)]
pub struct ReminderItem {
    pub id: Uuid,
    #[serde(rename = "type")]
    pub kind: String,
    pub title: String,
    pub due_at: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<serde_json::Value>,
}

/// Réponse de `GET /v1/reminders`.
#[derive(Serialize)]
pub struct RemindersResponse {
    pub data: Vec<ReminderItem>,
}

/// Le rappel `appointment` — prochain RDV réel du patient, RLS scoped via
/// `app.patient_account_id` (policy `appointment_patient_read`, migration 0029),
/// puis `app.current_cabinet_id` pour lire `provider`/`cabinet` (comme
/// `GET /v1/appointments/:id`, appointments.rs:754-796).
/// Aucun RDV futur confirmé → pas de rappel `appointment` (au lieu d'un RDV
/// fictif), ou `sqlx::Error`. Isolé pour permettre un appel BEST-EFFORT depuis
/// `list_reminders`, comme `fetch_sent_quotes`.
async fn fetch_next_appointment(
    state: &AppState,
    account_id: Uuid,
) -> Result<Option<ReminderItem>, sqlx::Error> {
    let mut tx = state.db.begin().await?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(account_id.to_string())
        .execute(&mut *tx)
        .await?;

    let appt = sqlx::query(
        "SELECT id, starts_at, cabinet_id, practitioner_id FROM appointment \
         WHERE status IN ('confirmed','checked_in') AND starts_at > now() \
           AND deleted_at IS NULL \
         ORDER BY starts_at ASC LIMIT 1",
    )
    .fetch_optional(&mut *tx)
    .await?;

    let Some(appt) = appt else {
        tx.commit().await?;
        return Ok(None);
    };

    let appointment_id: Uuid = appt.try_get("id")?;
    let starts_at: chrono::DateTime<chrono::Utc> = appt.try_get("starts_at")?;
    let cabinet_id: Uuid = appt.try_get("cabinet_id")?;
    let practitioner_id: Uuid = appt.try_get("practitioner_id")?;

    // Scope cabinet pour provider_cabinet_manage + tenant_isolation (cabinet).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await?;

    let practitioner: Option<String> =
        sqlx::query("SELECT display_name FROM provider WHERE practitioner_id = $1 LIMIT 1")
            .bind(practitioner_id)
            .fetch_optional(&mut *tx)
            .await?
            .map(|r| r.try_get("display_name"))
            .transpose()?;

    let cabinet_name: Option<String> =
        sqlx::query("SELECT raison_sociale FROM cabinet WHERE id = $1")
            .bind(cabinet_id)
            .fetch_optional(&mut *tx)
            .await?
            .map(|r| r.try_get("raison_sociale"))
            .transpose()?;

    tx.commit().await?;

    Ok(Some(ReminderItem {
        id: appointment_id,
        kind: "appointment".to_string(),
        title: "Prochain rendez-vous de contrôle".to_string(),
        due_at: starts_at.to_rfc3339(),
        status: "pending".to_string(),
        metadata: Some(serde_json::json!({
            "cabinet_name": cabinet_name,
            "practitioner": practitioner,
        })),
    }))
}

/// `GET /v1/reminders` — rappels de suivi et prévention du patient authentifié.
///
/// Le rappel `quote` (devis à signer) est dérivé des devis réels du patient :
/// un rappel par devis `status = 'sent'` (envoyé par le cabinet, en attente de
/// signature), RLS scoped via `app.patient_account_id` (policy `quote_patient_read`,
/// migration 0029), comme `GET /v1/dashboard`. Aucun devis en attente → aucun
/// rappel `quote`.
/// Triés par `due_at ASC` (plus urgents en premier).
/// Aucun rappel → `{ data: [] }`.
/// Devis `sent` (en attente de signature) du patient scopé, ou `sqlx::Error`.
/// Isolé pour permettre un appel BEST-EFFORT depuis `list_reminders` : une DB
/// indisponible ou une requête en échec ne doit PAS faire échouer tout l'écran
/// rappels (postmortem 2026-07-12 #3648 : la requête renvoyait 500 au lieu de
/// dégrader gracieusement).
async fn fetch_sent_quotes(
    state: &AppState,
    account_id: Uuid,
) -> Result<Vec<(Uuid, chrono::DateTime<chrono::Utc>)>, sqlx::Error> {
    let mut tx = state.db.begin().await?;
    // Scope patient — quote_patient_read (migration 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(account_id.to_string())
        .execute(&mut *tx)
        .await?;
    let rows = sqlx::query(
        "SELECT id, updated_at FROM quote \
         WHERE status = 'sent' AND deleted_at IS NULL \
         ORDER BY updated_at ASC",
    )
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        out.push((row.try_get("id")?, row.try_get("updated_at")?));
    }
    Ok(out)
}

/// Libellé FR pour `reminder.kind` (migration 0085, CHECK
/// `rdv_rappel|rdv_confirmation|rdv_follow_up`).
fn reminder_kind_title(kind: &str) -> &'static str {
    match kind {
        "rdv_confirmation" => "Confirmation de rendez-vous requise",
        "rdv_follow_up" => "Suivi après votre rendez-vous",
        _ => "Rappel de rendez-vous",
    }
}

/// Rappels planifiés réels (#4077) : table `reminder` (migration 0085),
/// jusqu'ici jamais interrogée par ce handler (données mockées). RLS scoped
/// via `app.patient_account_id` (policy `reminder_patient_read`, migration
/// 0171, cross-cabinet comme `fetch_next_appointment`/`fetch_sent_quotes`).
/// Seuls les rappels `pending` sont exposés (envoyés/échoués/annulés ne sont
/// pas des rappels à venir). Isolé pour un appel BEST-EFFORT.
async fn fetch_scheduled_reminders(
    state: &AppState,
    account_id: Uuid,
) -> Result<Vec<ReminderItem>, sqlx::Error> {
    let mut tx = state.db.begin().await?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(account_id.to_string())
        .execute(&mut *tx)
        .await?;

    let rows = sqlx::query(
        "SELECT id, kind, scheduled_at FROM reminder \
         WHERE status = 'pending' \
         ORDER BY scheduled_at ASC",
    )
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        let id: Uuid = row.try_get("id")?;
        let kind: String = row.try_get("kind")?;
        let scheduled_at: chrono::DateTime<chrono::Utc> = row.try_get("scheduled_at")?;
        out.push(ReminderItem {
            id,
            title: reminder_kind_title(&kind).to_string(),
            kind,
            due_at: scheduled_at.to_rfc3339(),
            status: "pending".to_string(),
            metadata: None,
        });
    }
    Ok(out)
}

pub async fn list_reminders(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<RemindersResponse>, AppError> {
    // Le rappel "prevention" était un littéral codé en dur (même id/titre pour
    // TOUT patient, due_at fixe s'enfonçant dans le passé) — donnée factice
    // servie en prod, sans base clinique réelle (#3880). Retiré plutôt
    // qu'inventé : aucune donnée de suivi (dernier détartrage, etc.) n'existe
    // encore côté modèle pour le calculer dynamiquement.
    let mut data: Vec<ReminderItem> = Vec::new();

    // BEST-EFFORT : une DB indisponible ou une requête RDV en échec ne doit pas
    // faire échouer tout l'écran rappels (on renvoie au moins les autres rappels).
    match fetch_next_appointment(&state, claims.account_id).await {
        Ok(Some(item)) => data.push(item),
        Ok(None) => {}
        Err(err) => {
            tracing::warn!(%err, "list_reminders: rappel RDV indisponible (best-effort)");
        }
    }

    // BEST-EFFORT : une DB indisponible ou une requête devis en échec ne doit pas
    // faire échouer tout l'écran rappels (on renvoie au moins le rappel RDV).
    let sent_quotes = match fetch_sent_quotes(&state, claims.account_id).await {
        Ok(rows) => rows,
        Err(err) => {
            tracing::warn!(%err, "list_reminders: rappels devis indisponibles (best-effort)");
            Vec::new()
        }
    };

    for (quote_id, updated_at) in sent_quotes {
        data.push(ReminderItem {
            id: quote_id,
            // #3795 : quote_id présenté comme document_id (type "document")
            // violait le contrat type:document ⇒ document_id résoluble via
            // GET /documents/:id — aucune ligne `document` ne correspond,
            // donc 404 systématique (cul-de-sac). "quote"/"quote_id" est le
            // bon type, cohérent avec dashboard.to_sign.quote_id.
            kind: "quote".to_string(),
            title: "Devis à signer avant votre prochain soin".to_string(),
            due_at: updated_at.to_rfc3339(),
            status: "pending".to_string(),
            metadata: Some(serde_json::json!({ "quote_id": quote_id })),
        });
    }

    // BEST-EFFORT : une DB indisponible ou une requête rappels en échec ne
    // doit pas faire échouer tout l'écran (#4077).
    match fetch_scheduled_reminders(&state, claims.account_id).await {
        Ok(items) => data.extend(items),
        Err(err) => {
            tracing::warn!(%err, "list_reminders: rappels planifiés indisponibles (best-effort)");
        }
    }

    // Tri global par due_at ASC (plus urgents en premier) — trois sources
    // désormais mélangées (appointment/quote/reminder), chacune déjà triée
    // individuellement mais pas entre elles avant ce tri final (#4077).
    data.sort_by(|a, b| a.due_at.cmp(&b.due_at));

    Ok(Json(RemindersResponse { data }))
}
