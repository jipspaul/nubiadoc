//! Handler `POST /v1/invoices/:id/reminder` — relance manuelle d'une facture
//! (devis signé) impayée envoyée au patient (#7206).
//!
//! "Facture" = devis `signed`, même terminologie que `patient_alerts.rs`
//! (`kind: "unpaid_invoice"`) : aucune table `invoice` distincte n'existe
//! dans ce dépôt. Déclenchée par un membre du cabinet (praticien/secrétariat),
//! contrairement à `quote_relance_dispatch.rs` (worker périodique qui relance
//! un devis NON signé en attente de signature — logique différente).
//!
//! Canaux : in-app + push (`notify::notify_patient_account`, payload sans
//! PII/montant, même contrainte que le reste de `notify.rs`) puis e-mail
//! (`Mailer::send_invoice_reminder`, montant inclus — canal direct au
//! patient, comme `send_access_request`) si le push a résolu un compte app
//! avec une adresse connue. Patient sans compte app (walk-in) : aucun canal
//! disponible, aucune ligne `invoice_reminder` n'est créée puisque rien n'a
//! été envoyé.
//!
//! Garde-fou anti-spam (#7206) : une seule relance par 7 jours par facture,
//! `409 invoice_reminder_cooldown` sinon.

use axum::{
    extract::{Extension, Path, State},
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    notify,
    patient_tags::ensure_secretary_scope,
    AppState, JobDispatcher,
};

const REMINDER_COOLDOWN_DAYS: i32 = 7;

/// Réponse de `POST /v1/invoices/:id/reminder`.
#[derive(Serialize)]
pub struct InvoiceReminderResponse {
    pub sent: bool,
    pub channels: Vec<String>,
    pub balance_due_cents: i64,
}

/// `POST /v1/invoices/:id/reminder` — relance patient sur facture impayée (#7206).
///
/// `ProSecretaryPlusClaims` : praticien/secrétariat (scope secrétariat R10
/// appliqué via `ensure_secretary_scope`, même garde que
/// `patient_alerts::get_patient_alerts`). `:id` = identifiant du devis signé
/// ("facture") — introuvable, hors tenant ou pas `signed` -> `404`. Une
/// relance déjà envoyée dans les 7 derniers jours pour cette facture ->
/// `409 invoice_reminder_cooldown`.
pub async fn send_invoice_reminder(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<InvoiceReminderResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Facture = devis signé (même terminologie que patient_alerts.rs) : un
    // devis non signé ou hors tenant n'est pas une facture -> 404.
    let quote_row = sqlx::query(
        "SELECT patient_id FROM quote \
         WHERE id = $1 AND cabinet_id = $2 AND status = 'signed' AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let patient_id: Uuid = quote_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    ensure_secretary_scope(&mut tx, &claims, patient_id).await?;

    // Garde-fou : une seule relance par 7 jours par facture (#7206).
    let recent = sqlx::query(
        "SELECT 1 FROM invoice_reminder \
         WHERE invoice_id = $1 AND cabinet_id = $2 \
           AND sent_at > now() - make_interval(days => $3)",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .bind(REMINDER_COOLDOWN_DAYS)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if recent.is_some() {
        return Err(AppError::InvoiceReminderCooldown);
    }

    // Reste dû sur CETTE facture — même formule que
    // `patient_alerts::get_patient_alerts` (part patient nette moins les
    // paiements enregistrés), scopée à ce devis plutôt qu'agrégée sur tous
    // les devis signés du patient.
    let balance_row = sqlx::query(
        "SELECT (( \
           COALESCE((SELECT SUM(qi.qty * qi.unit_amount \
                             - COALESCE(qi.amo_part, 0) - COALESCE(qi.amc_part, 0)) \
                     FROM quote_item qi WHERE qi.quote_id = $1), 0) \
           - \
           COALESCE((SELECT SUM(amount) FROM payment \
                     WHERE quote_id = $1 AND cabinet_id = $2 \
                       AND status IN ('pending', 'paid')), 0) \
         ) * 100)::bigint AS balance_due_cents",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let balance_due_cents: i64 = balance_row
        .try_get("balance_due_cents")
        .map_err(|_| AppError::Internal)?;

    // Compte app du patient (`patient.patient_account_id`, colonne cabinet,
    // lisible sans GUC supplémentaire) : seul canal connu pour l'in-app/push.
    // `None` pour un patient walk-in sans compte -> aucun canal disponible.
    let patient_account_id: Option<Uuid> = sqlx::query_scalar(
        "SELECT patient_account_id FROM patient WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut channels: Vec<String> = Vec::new();
    let mut push_target: Option<(Uuid, Uuid)> = None;

    if let Some(account_id) = patient_account_id {
        push_target = notify::notify_patient_account(
            &mut tx,
            account_id,
            "invoice_reminder",
            "Une facture reste impayée",
            serde_json::json!({ "invoice_id": id }),
        )
        .await?;
    }

    if let Some((app_user_id, _)) = push_target {
        sqlx::query(
            "INSERT INTO invoice_reminder (invoice_id, cabinet_id, channel, sent_by) \
             VALUES ($1, $2, 'push', $3)",
        )
        .bind(id)
        .bind(claims.cabinet_id)
        .bind(claims.sub)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        channels.push("push".to_string());

        // `app.current_user_id` est déjà posé sur `app_user_id` par
        // `notify_user` (appelé via `notify_patient_account` ci-dessus) —
        // satisfait `user_self_select` sans GUC/requête supplémentaire.
        let email: Option<String> = sqlx::query_scalar("SELECT email FROM app_user WHERE id = $1")
            .bind(app_user_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        if let Some(email) = email {
            state
                .mailer
                .send_invoice_reminder(&email, balance_due_cents);
            sqlx::query(
                "INSERT INTO invoice_reminder (invoice_id, cabinet_id, channel, sent_by) \
                 VALUES ($1, $2, 'email', $3)",
            )
            .bind(id)
            .bind(claims.cabinet_id)
            .bind(claims.sub)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
            channels.push("email".to_string());
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Push APRÈS commit (même convention que sign_quote/orders.rs) : jamais
    // d'enfilage FCM avant que l'écriture DB soit garantie.
    if let Some((app_user_id, notification_id)) = push_target {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        invoice_id = %id,
        channels = ?channels,
        "invoice reminder sent"
    );

    Ok(Json(InvoiceReminderResponse {
        sent: !channels.is_empty(),
        channels,
        balance_due_cents,
    }))
}

/// Une relance enregistrée (`invoice_reminder`, migration 0275).
#[derive(Serialize)]
pub struct InvoiceReminderHistoryItem {
    pub channel: String,
    pub sent_at: String,
}

/// Réponse de `GET /v1/invoices/:id/reminders`.
#[derive(Serialize)]
pub struct InvoiceReminderHistoryResponse {
    pub data: Vec<InvoiceReminderHistoryItem>,
}

/// `GET /v1/invoices/:id/reminders` — historique des relances patient sur
/// une facture (#7205, front secrétariat/praticien pour l'affichage sous le
/// bouton « Relancer le patient »). Même garde que le `POST` ci-dessus
/// (`ProSecretaryPlusClaims`) : `:id` = devis signé. Trié `sent_at DESC`
/// (la relance la plus récente en tête) — inverse de
/// `quote_relances::list_quote_relances` qui liste des jalons J+3/J+7
/// intrinsèquement chronologiques, alors qu'ici chaque ligne est un
/// événement répétable dont le plus récent est ce qui intéresse l'utilisateur.
pub async fn list_invoice_reminders(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<InvoiceReminderHistoryResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let quote_exists =
        sqlx::query("SELECT 1 FROM quote WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL")
            .bind(id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if quote_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let rows = sqlx::query(
        "SELECT channel, sent_at FROM invoice_reminder \
         WHERE invoice_id = $1 AND cabinet_id = $2 \
         ORDER BY sent_at DESC",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data: Vec<InvoiceReminderHistoryItem> = Vec::with_capacity(rows.len());
    for row in rows {
        let channel: String = row.try_get("channel").map_err(|_| AppError::Internal)?;
        let sent_at: chrono::DateTime<chrono::Utc> =
            row.try_get("sent_at").map_err(|_| AppError::Internal)?;
        data.push(InvoiceReminderHistoryItem {
            channel,
            sent_at: sent_at.to_rfc3339(),
        });
    }

    Ok(Json(InvoiceReminderHistoryResponse { data }))
}
