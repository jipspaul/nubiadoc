//! Worker de dispatch des rappels RDV (canal push) — #4034.
//!
//! Quoi : lit `reminder` (migration 0085) où `status='pending' AND
//! scheduled_at<=now()`, crée la notification in-app correspondante et
//! déclenche l'envoi push (`JobDispatcher::enqueue_push_notification`), puis
//! marque `sent`/`failed`.
//!
//! Quand : boucle périodique lancée en `tokio::spawn` depuis `main.rs`, pas
//! un job apalis — aucune implémentation apalis/Redis n'existe dans ce dépôt
//! à ce jour (`JobDispatcher` documente "post-T2", cf. `api/src/lib.rs`).
//! Même raccourci documenté que `interop::subscription::dispatch_notification`
//! (travail fait en synchrone/best-effort côté binaire plutôt que via un vrai
//! job queue absent). ADR-002/ADR-012 : monolithe modulaire, un `tokio::spawn`
//! de plus dans le même binaire (comme le listener MLLP), pas un second service.
//!
//! Pourquoi cette approche : `reminder` est une table TENANT (cabinet_id,
//! RLS `tenant_isolation`), mais le balayage est intrinsèquement CROSS-CABINET
//! (un seul worker, tous les cabinets). `due_reminders_for_dispatch`
//! (SECURITY DEFINER, migration 0156) résout patient → patient_account_id →
//! app_user_id → présence d'un device actif côté SQL, sans jamais exposer
//! `patient_account` brut à ce contexte système (même garde que
//! `ensure_patient_for_cabinet`, migration 0123).
//!
//! Modes d'échec : patient non lié à un compte, ou aucun device actif →
//! `status='failed'`. Un rappel individuellement en erreur (ex. contrainte
//! DB) est loggé et compté `failed` — ne fait JAMAIS paniquer le balayage
//! des autres rappels dus.

use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::{auth::AppError, notify, JobDispatcher};

/// Résumé d'une passe de dispatch (logs/tests).
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct ReminderDispatchSummary {
    pub sent: u32,
    pub failed: u32,
}

/// Erreur d'une passe de dispatch — type dédié (pas `AppError`, `pub(crate)`
/// et donc invisible depuis `api/tests/`) pour que `dispatch_pending_reminders`
/// reste appelable directement par les tests d'intégration, comme demandé
/// par le critère d'acceptation de #4034.
#[derive(Debug)]
pub struct ReminderDispatchError(String);

impl std::fmt::Display for ReminderDispatchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "reminder dispatch error: {}", self.0)
    }
}

impl std::error::Error for ReminderDispatchError {}

impl From<AppError> for ReminderDispatchError {
    fn from(err: AppError) -> Self {
        Self(format!("{err:?}"))
    }
}

/// Titre générique par `kind` de rappel (zéro PII, même contrainte que
/// `notify.rs` : le contenu réel se charge authentifié à l'ouverture de l'app).
fn title_for_kind(kind: &str) -> &'static str {
    match kind {
        "rdv_confirmation" => "Confirmez votre rendez-vous",
        "rdv_follow_up" => "Comment s'est passé votre rendez-vous ?",
        _ => "Rappel de rendez-vous",
    }
}

/// Traite tous les rappels dus. Ne panique jamais sur un rappel individuel
/// en erreur : le balayage continue, l'erreur se traduit par `status='failed'`
/// sur CE rappel (ou reste 'pending' si même l'UPDATE échoue — repris au
/// prochain passage).
pub async fn dispatch_pending_reminders(
    db: &PgPool,
    dispatcher: &dyn JobDispatcher,
) -> Result<ReminderDispatchSummary, ReminderDispatchError> {
    let due = sqlx::query(
        "SELECT reminder_id, cabinet_id, appointment_id, kind, app_user_id, has_active_device \
         FROM due_reminders_for_dispatch()",
    )
    .fetch_all(db)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut summary = ReminderDispatchSummary::default();

    for row in due {
        let reminder_id: Uuid = row.try_get("reminder_id").map_err(|_| AppError::Internal)?;
        let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
        let appointment_id: Uuid = row
            .try_get("appointment_id")
            .map_err(|_| AppError::Internal)?;
        let kind: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
        let app_user_id: Option<Uuid> =
            row.try_get("app_user_id").map_err(|_| AppError::Internal)?;
        let has_active_device: bool = row
            .try_get("has_active_device")
            .map_err(|_| AppError::Internal)?;

        match process_one_reminder(
            db,
            reminder_id,
            cabinet_id,
            appointment_id,
            &kind,
            app_user_id,
            has_active_device,
        )
        .await
        {
            Ok(Some((uid, notification_id))) => {
                // Push enqueue APRÈS commit (fire-and-forget), même convention
                // que orders.rs/quotes.rs/stock.rs.
                dispatcher.enqueue_push_notification(uid, notification_id);
                summary.sent += 1;
            }
            Ok(None) => {
                summary.failed += 1;
            }
            Err(err) => {
                tracing::warn!(
                    reminder_id = %reminder_id,
                    error = ?err,
                    "reminder_dispatch: échec traitement d'un rappel (sans interrompre le balayage)"
                );
                summary.failed += 1;
            }
        }
    }

    Ok(summary)
}

/// Traite un rappel : crée la notification in-app + marque `sent` si un
/// device actif existe, marque `failed` sinon. Le tout dans UNE transaction
/// (notification + UPDATE reminder) pour éviter une notification dupliquée
/// si un retry reprend un rappel resté "pending" suite à un échec partiel.
///
/// Retourne `Some((app_user_id, notification_id))` si envoyé, `None` si
/// marqué `failed` (patient non lié à un compte, ou aucun device actif).
async fn process_one_reminder(
    db: &PgPool,
    reminder_id: Uuid,
    cabinet_id: Uuid,
    appointment_id: Uuid,
    kind: &str,
    app_user_id: Option<Uuid>,
    has_active_device: bool,
) -> Result<Option<(Uuid, Uuid)>, AppError> {
    let mut tx = db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope RLS tenant du rappel (policy tenant_isolation, migration 0085)
    // pour l'UPDATE ci-dessous.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let outcome = if let (Some(uid), true) = (app_user_id, has_active_device) {
        let notification_id = notify::notify_user(
            &mut tx,
            uid,
            kind,
            title_for_kind(kind),
            serde_json::json!({ "appointment_id": appointment_id, "reminder_id": reminder_id }),
        )
        .await?;
        Some((uid, notification_id))
    } else {
        None
    };

    let new_status = if outcome.is_some() { "sent" } else { "failed" };
    sqlx::query(
        "UPDATE reminder \
         SET status = $1, sent_at = CASE WHEN $1 = 'sent' THEN now() ELSE sent_at END \
         WHERE id = $2",
    )
    .bind(new_status)
    .bind(reminder_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(outcome)
}

/// Boucle périodique appelée depuis `main.rs` (`tokio::spawn`, cf. doc de
/// module). Tourne indéfiniment ; une erreur de passe est loggée, jamais
/// fatale (le process HTTP ne doit pas s'arrêter pour un souci de rappels).
pub async fn run_dispatch_loop(
    db: PgPool,
    dispatcher: std::sync::Arc<dyn JobDispatcher>,
    interval: std::time::Duration,
) {
    let mut ticker = tokio::time::interval(interval);
    loop {
        ticker.tick().await;
        match dispatch_pending_reminders(&db, dispatcher.as_ref()).await {
            Ok(summary) if summary.sent > 0 || summary.failed > 0 => {
                tracing::info!(
                    sent = summary.sent,
                    failed = summary.failed,
                    "reminder_dispatch: passe terminée"
                );
            }
            Ok(_) => {}
            Err(err) => {
                tracing::error!(error = ?err, "reminder_dispatch: passe en échec");
            }
        }
    }
}
