//! Handler `GET /v1/dashboard` — vue agrégée patient.

use axum::{extract::State, Json};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

#[derive(Serialize)]
pub struct NextAppointment {
    pub appointment_id: Uuid,
    pub starts_at: String,
    pub status: String,
}

#[derive(Serialize)]
pub struct ToSignItem {
    pub quote_id: Uuid,
    pub amount_cents: i64,
}

#[derive(Serialize)]
pub struct ToPayItem {
    pub quote_id: Uuid,
    pub amount_cents: i64,
}

#[derive(Serialize)]
pub struct DashboardResponse {
    pub next_appointment: Option<NextAppointment>,
    pub to_sign: Vec<ToSignItem>,
    pub to_pay: Vec<ToPayItem>,
    pub unread_messages: i64,
    pub reminders: i64,
}

/// `GET /v1/dashboard` — vue agrégée patient (US-P13).
///
/// Token `kind:"patient"` requis — les tokens pro reçoivent 403.
/// RLS scoped via `app.patient_account_id` (migration 0029) : le patient ne voit
/// que ses propres données, tous cabinets confondus.
/// 5 requêtes dans une seule transaction (pas de N+1).
pub async fn get_dashboard(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<DashboardResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Scope utilisateur pour la lecture des notifications (policy notification_owner_select).
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Prochain RDV futur confirmé — index appointment_patient_idx (0012)
    let appt = sqlx::query(
        "SELECT id, starts_at, status FROM appointment \
         WHERE status IN ('confirmed','checked_in') AND starts_at > now() \
         ORDER BY starts_at LIMIT 1",
    )
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Devis à signer (envoyés au patient) — index quote_cabinet_status_idx (0012)
    let quotes = sqlx::query(
        "SELECT id, (total_amount * 100)::bigint AS amount_cents \
         FROM quote \
         WHERE status = 'sent' AND deleted_at IS NULL",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Reste à charge (#6566) : un devis SIGNÉ reste une dette tant que les
    // paiements pending/paid qui lui sont associés ne couvrent pas son total —
    // même définition que le solde cabinet (patient_detail.rs, clinical.rs) :
    // un PaymentIntent `pending` est une intention DÉJÀ engagée par le patient,
    // donc il réduit la dette au lieu de s'y ajouter. Agrégé par `quote_id`
    // (GROUP BY) pour ne pas compter en double plusieurs intents pending sur
    // le même devis, et borné par devis via le WHERE (jamais négatif).
    let dues = sqlx::query(
        "SELECT q.id, ((q.total_amount - COALESCE(p.paid_amount, 0)) * 100)::bigint AS amount_cents \
         FROM quote q \
         LEFT JOIN ( \
           SELECT quote_id, SUM(amount) AS paid_amount FROM payment \
           WHERE status IN ('pending', 'paid') AND quote_id IS NOT NULL \
           GROUP BY quote_id \
         ) p ON p.quote_id = q.id \
         WHERE q.status = 'signed' AND q.deleted_at IS NULL \
           AND q.total_amount > COALESCE(p.paid_amount, 0)",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Messages non lus envoyés par un soignant (cabinet ou pharmacie)
    let msg_row = sqlx::query(
        "SELECT COUNT(*) AS cnt FROM message \
         WHERE sender_kind IN ('practitioner','secretary','pharmacist') AND read_at IS NULL",
    )
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Rappels (US-P13) : reflète EXACTEMENT ce que calcule GET /v1/reminders
    // (reminders.rs), pas un COUNT sur `notification` — `kind='appointment_reminder'`
    // n'y est émis par aucun émetteur, ce compteur était donc structurellement
    // toujours à 0 (#3888). 1 si un prochain RDV confirmé/checked_in existe
    // (reminders.rs n'en affiche jamais qu'un seul, d'où le booléen plutôt
    // qu'un COUNT) + un devis `sent` par rappel document. Le rappel "prevention"
    // codé en dur a été retiré de reminders.rs (#3880) — plus de +1 fixe ici.
    let reminders: i64 = if appt.is_some() { 1 } else { 0 } + quotes.len() as i64;

    let next_appointment = appt
        .map(|row| -> Result<NextAppointment, AppError> {
            let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let starts_at: chrono::DateTime<chrono::Utc> =
                row.try_get("starts_at").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            Ok(NextAppointment {
                appointment_id,
                starts_at: starts_at.to_rfc3339(),
                status,
            })
        })
        .transpose()?;

    let to_sign = quotes
        .into_iter()
        .map(|row| -> Result<ToSignItem, AppError> {
            let quote_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let amount_cents: i64 = row
                .try_get("amount_cents")
                .map_err(|_| AppError::Internal)?;
            Ok(ToSignItem {
                quote_id,
                amount_cents,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    let to_pay = dues
        .into_iter()
        .map(|row| -> Result<ToPayItem, AppError> {
            let quote_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let amount_cents: i64 = row
                .try_get("amount_cents")
                .map_err(|_| AppError::Internal)?;
            Ok(ToPayItem {
                quote_id,
                amount_cents,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    let unread_messages: i64 = msg_row.try_get("cnt").map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        unread_messages,
        reminders,
        "dashboard aggregated"
    );

    Ok(Json(DashboardResponse {
        next_appointment,
        to_sign,
        to_pay,
        unread_messages,
        reminders,
    }))
}
