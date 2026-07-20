//! Worker de dispatch des rappels RDV (canaux push + sms) — #4034, #4036.
//!
//! Quoi : lit `reminder` (migration 0085) où `status='pending' AND
//! scheduled_at<=now()`, puis selon `channel` : crée la notification in-app
//! et déclenche l'envoi push (`JobDispatcher::enqueue_push_notification`),
//! ou envoie un SMS (`SmsSender::send`) ; marque `sent`/`failed`/`cancelled`.
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
//! (SECURITY DEFINER, migration 0156, étendue par 0157) résout patient →
//! patient_account_id → app_user_id/phone/opt-in SMS côté SQL, sans jamais
//! exposer `patient_account` brut à ce contexte système (même garde que
//! `ensure_patient_for_cabinet`, migration 0123).
//!
//! Modes d'échec : `channel='push'` sans device actif, `channel='sms'` sans
//! numéro connu, ou tout autre canal non géré (ex. `email`, pas encore
//! implémenté) → `status='failed'`. `channel='sms'` avec opt-out patient
//! (`notification_preference.sms_rdv=false`) → `status='cancelled'` (choix
//! du patient, pas un échec). Un rappel individuellement en erreur (ex.
//! contrainte DB) est loggé et compté `failed` — ne fait JAMAIS paniquer le
//! balayage des autres rappels dus.

use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::{auth::AppError, notify, JobDispatcher, SmsSender};

/// Résumé d'une passe de dispatch (logs/tests).
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct ReminderDispatchSummary {
    pub sent: u32,
    pub failed: u32,
    /// `channel='sms'` avec opt-out patient (`notification_preference.sms_rdv=false`,
    /// #4036) — choix du patient, pas un échec technique.
    pub cancelled: u32,
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

/// Corps du SMS par `kind` de rappel — même contrainte zéro-PII que
/// `title_for_kind` (pas de nom de patient/praticien, pas de motif de RDV).
fn sms_body_for_kind(kind: &str) -> &'static str {
    match kind {
        "rdv_confirmation" => {
            "Merci de confirmer votre prochain rendez-vous depuis l'application Nubia."
        }
        "rdv_follow_up" => {
            "Comment s'est passé votre rendez-vous ? Donnez votre avis dans l'application Nubia."
        }
        _ => "Rappel : vous avez un rendez-vous à venir. Détails dans l'application Nubia.",
    }
}

/// Action à effectuer APRÈS commit de la transaction du rappel (même
/// convention que le push existant : jamais d'appel provider externe avant
/// que l'écriture DB soit garantie).
enum DispatchAction {
    Push {
        app_user_id: Uuid,
        notification_id: Uuid,
    },
    Sms {
        phone: String,
        message: &'static str,
    },
    /// Rappel marqué `failed` — rien à envoyer.
    None,
    /// Rappel marqué `cancelled` (opt-out patient, #4036) — rien à envoyer,
    /// distinct de `None`/`failed` : ce n'est pas une erreur.
    Cancelled,
}

/// Traite tous les rappels dus. Ne panique jamais sur un rappel individuel
/// en erreur : le balayage continue, l'erreur se traduit par `status='failed'`
/// sur CE rappel (ou reste 'pending' si même l'UPDATE échoue — repris au
/// prochain passage).
pub async fn dispatch_pending_reminders(
    db: &PgPool,
    dispatcher: &dyn JobDispatcher,
    sms_sender: &dyn SmsSender,
) -> Result<ReminderDispatchSummary, ReminderDispatchError> {
    let due = sqlx::query(
        "SELECT reminder_id, cabinet_id, appointment_id, kind, channel, app_user_id, \
                has_active_device, phone, sms_opted_in \
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
        let channel: String = row.try_get("channel").map_err(|_| AppError::Internal)?;
        let app_user_id: Option<Uuid> =
            row.try_get("app_user_id").map_err(|_| AppError::Internal)?;
        let has_active_device: bool = row
            .try_get("has_active_device")
            .map_err(|_| AppError::Internal)?;
        let phone: Option<String> = row.try_get("phone").map_err(|_| AppError::Internal)?;
        let sms_opted_in: bool = row
            .try_get("sms_opted_in")
            .map_err(|_| AppError::Internal)?;

        match process_one_reminder(
            db,
            reminder_id,
            cabinet_id,
            appointment_id,
            &kind,
            &channel,
            app_user_id,
            has_active_device,
            phone,
            sms_opted_in,
        )
        .await
        {
            Ok(DispatchAction::Push {
                app_user_id,
                notification_id,
            }) => {
                // Push enqueue APRÈS commit (fire-and-forget), même convention
                // que orders.rs/quotes.rs/stock.rs.
                dispatcher.enqueue_push_notification(app_user_id, notification_id);
                summary.sent += 1;
            }
            Ok(DispatchAction::Sms { phone, message }) => {
                // SMS envoi APRÈS commit, même convention que le push : jamais
                // d'appel provider externe avant que l'UPDATE status='sent' soit garanti.
                sms_sender.send(&phone, message);
                summary.sent += 1;
            }
            Ok(DispatchAction::None) => {
                summary.failed += 1;
            }
            Ok(DispatchAction::Cancelled) => {
                summary.cancelled += 1;
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

/// Traite un rappel selon son `channel` :
/// - `push` : crée la notification in-app + marque `sent` si un device actif
///   existe pour le patient, `failed` sinon ;
/// - `sms` : marque `sent` si un numéro est connu ET le patient n'a pas
///   opté-out (`notification_preference.sms_rdv`, #4036), `cancelled` en cas
///   d'opt-out, `failed` si aucun numéro n'est connu ;
/// - tout autre canal (ex. `email`, pas encore implémenté) : `failed`.
///
/// Le tout dans UNE transaction (notification + UPDATE reminder) pour éviter
/// un envoi dupliqué si un retry reprend un rappel resté "pending" suite à
/// un échec partiel.
#[allow(clippy::too_many_arguments)]
async fn process_one_reminder(
    db: &PgPool,
    reminder_id: Uuid,
    cabinet_id: Uuid,
    appointment_id: Uuid,
    kind: &str,
    channel: &str,
    app_user_id: Option<Uuid>,
    has_active_device: bool,
    phone: Option<String>,
    sms_opted_in: bool,
) -> Result<DispatchAction, AppError> {
    let mut tx = db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope RLS tenant du rappel (policy tenant_isolation, migration 0085)
    // pour l'UPDATE ci-dessous.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (action, new_status): (DispatchAction, &str) = match channel {
        "push" => {
            if let (Some(uid), true) = (app_user_id, has_active_device) {
                let notification_id = notify::notify_user(
                    &mut tx,
                    uid,
                    kind,
                    title_for_kind(kind),
                    serde_json::json!({ "appointment_id": appointment_id, "reminder_id": reminder_id }),
                )
                .await?;
                (
                    DispatchAction::Push {
                        app_user_id: uid,
                        notification_id,
                    },
                    "sent",
                )
            } else {
                (DispatchAction::None, "failed")
            }
        }
        "sms" => match phone {
            Some(phone) if sms_opted_in => (
                DispatchAction::Sms {
                    phone,
                    message: sms_body_for_kind(kind),
                },
                "sent",
            ),
            Some(_) => (DispatchAction::Cancelled, "cancelled"),
            None => (DispatchAction::None, "failed"),
        },
        _ => (DispatchAction::None, "failed"),
    };

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

    Ok(action)
}

/// Boucle périodique appelée depuis `main.rs` (`tokio::spawn`, cf. doc de
/// module). Tourne indéfiniment ; une erreur de passe est loggée, jamais
/// fatale (le process HTTP ne doit pas s'arrêter pour un souci de rappels).
pub async fn run_dispatch_loop(
    db: PgPool,
    dispatcher: std::sync::Arc<dyn JobDispatcher>,
    sms_sender: std::sync::Arc<dyn SmsSender>,
    interval: std::time::Duration,
) {
    let mut ticker = tokio::time::interval(interval);
    loop {
        ticker.tick().await;
        match dispatch_pending_reminders(&db, dispatcher.as_ref(), sms_sender.as_ref()).await {
            Ok(summary) if summary.sent > 0 || summary.failed > 0 || summary.cancelled > 0 => {
                tracing::info!(
                    sent = summary.sent,
                    failed = summary.failed,
                    cancelled = summary.cancelled,
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
