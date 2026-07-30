//! Worker de relance des devis en attente de signature — #4126.
//!
//! Quoi : balaie `quote WHERE status='sent' AND sent_at IS NOT NULL`, et
//! pour chaque devis dont `sent_at` remonte à ≥3 jours (jalon `j3`) ou
//! ≥7 jours (jalon `j7`) et n'a pas encore reçu ce jalon
//! (`quote_relance`, migration 0207), notifie le patient et enregistre le
//! jalon. Un devis atteignant les deux seuils au même passage reçoit les
//! deux notifications (rare — passage toutes les `interval`, largement
//! sous 4 jours).
//!
//! Quand : boucle périodique `tokio::spawn` dans le même binaire, même
//! pattern que `reminder_dispatch.rs` (pas de job apalis dans ce dépôt à
//! ce jour — voir sa doc de module pour le détail du choix).
//!
//! Pourquoi cette approche : `quote` est une table TENANT (cabinet_id, RLS
//! `tenant_isolation`), le balayage est cross-cabinet (un seul worker, tous
//! les cabinets) — même limite déjà documentée pour `reminder_dispatch.rs`.
//! Contrairement au dispatch de rappels (qui délègue la résolution
//! patient → device/téléphone à une fonction SECURITY DEFINER), la
//! notification de relance est purement in-app (`notify::notify_patient_account`,
//! zéro PII dans le payload) : pas besoin d'un tel contournement RLS ici.

use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::{auth::AppError, notify};

/// Résumé d'une passe de dispatch (logs/tests).
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct QuoteRelanceDispatchSummary {
    pub j3_sent: u32,
    pub j7_sent: u32,
}

/// Erreur d'une passe de dispatch — type dédié (pas `AppError`, invisible
/// depuis `api/tests/`), même convention que `ReminderDispatchError`.
#[derive(Debug)]
pub struct QuoteRelanceDispatchError(String);

impl std::fmt::Display for QuoteRelanceDispatchError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "quote relance dispatch error: {}", self.0)
    }
}

impl std::error::Error for QuoteRelanceDispatchError {}

impl From<AppError> for QuoteRelanceDispatchError {
    fn from(err: AppError) -> Self {
        Self(format!("{err:?}"))
    }
}

/// Tente d'enregistrer le jalon `milestone` pour `quote_id` si `days_since >=
/// threshold` et qu'il n'a pas déjà été envoyé (`UNIQUE(quote_id, milestone)`,
/// migration 0207 — `ON CONFLICT DO NOTHING` fait office de garde
/// idempotente sans lecture préalable). Notifie le patient seulement si la
/// ligne a effectivement été insérée (évite un doublon si deux passages du
/// worker se chevauchent).
async fn maybe_send_milestone(
    db: &PgPool,
    cabinet_id: Uuid,
    quote_id: Uuid,
    patient_account_id: Option<Uuid>,
    days_since: i64,
    threshold: i64,
    milestone: &str,
) -> Result<bool, AppError> {
    if days_since < threshold {
        return Ok(false);
    }

    let mut tx = db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let inserted = sqlx::query(
        "INSERT INTO quote_relance (cabinet_id, quote_id, milestone) \
         VALUES ($1, $2, $3) \
         ON CONFLICT (quote_id, milestone) DO NOTHING \
         RETURNING id",
    )
    .bind(cabinet_id)
    .bind(quote_id)
    .bind(milestone)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let did_insert = inserted.is_some();

    if did_insert {
        if let Some(account_id) = patient_account_id {
            notify::notify_patient_account(
                &mut tx,
                account_id,
                "quote_relance",
                "Un devis vous attend",
                serde_json::json!({ "quote_id": quote_id }),
            )
            .await?;
        }
        // Patient sans compte app (walk-in, devis créé côté cabinet) :
        // jalon quand même enregistré (évite de re-tenter chaque passage),
        // notification silencieusement absente — même choix que
        // `consultations::complete_consultation` pour `review_request`.
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(did_insert)
}

/// Traite tous les devis `sent` dus pour une relance. Ne panique jamais sur
/// un devis individuel en erreur : le balayage continue, l'erreur est
/// loggée et ce devis sera retenté au prochain passage (aucun état
/// intermédiaire n'est écrit en cas d'échec, `quote_relance` n'existe que
/// si la transaction a commité).
pub async fn dispatch_quote_relances(
    db: &PgPool,
) -> Result<QuoteRelanceDispatchSummary, QuoteRelanceDispatchError> {
    // due_quotes_for_relance() (SECURITY DEFINER, migration 0208) — même
    // besoin de contournement RLS cross-cabinet que due_reminders_for_dispatch
    // (0156, #4034) : une simple SELECT sur `quote` sous nubia_app sans GUC
    // cabinet ne verrait jamais aucune ligne (tenant_isolation).
    let due = sqlx::query("SELECT * FROM due_quotes_for_relance()")
        .fetch_all(db)
        .await
        .map_err(|_| AppError::Internal)?;

    let mut summary = QuoteRelanceDispatchSummary::default();

    for row in due {
        let quote_id: Uuid = row.try_get("quote_id").map_err(|_| AppError::Internal)?;
        let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
        let patient_account_id: Option<Uuid> = row
            .try_get("patient_account_id")
            .map_err(|_| AppError::Internal)?;
        let days_since: f64 = row
            .try_get("days_since_sent")
            .map_err(|_| AppError::Internal)?;
        let days_since = days_since as i64;

        match maybe_send_milestone(
            db,
            cabinet_id,
            quote_id,
            patient_account_id,
            days_since,
            3,
            "j3",
        )
        .await
        {
            Ok(true) => summary.j3_sent += 1,
            Ok(false) => {}
            Err(err) => {
                tracing::warn!(quote_id = %quote_id, milestone = "j3", error = ?err,
                    "quote_relance_dispatch: échec traitement (sans interrompre le balayage)");
            }
        }

        match maybe_send_milestone(
            db,
            cabinet_id,
            quote_id,
            patient_account_id,
            days_since,
            7,
            "j7",
        )
        .await
        {
            Ok(true) => summary.j7_sent += 1,
            Ok(false) => {}
            Err(err) => {
                tracing::warn!(quote_id = %quote_id, milestone = "j7", error = ?err,
                    "quote_relance_dispatch: échec traitement (sans interrompre le balayage)");
            }
        }
    }

    Ok(summary)
}

/// Boucle périodique appelée depuis `main.rs`. Tourne indéfiniment ; une
/// erreur de passe est loggée, jamais fatale.
pub async fn run_quote_relance_loop(db: PgPool, interval: std::time::Duration) {
    let mut ticker = tokio::time::interval(interval);
    loop {
        ticker.tick().await;
        match dispatch_quote_relances(&db).await {
            Ok(summary) if summary.j3_sent > 0 || summary.j7_sent > 0 => {
                tracing::info!(
                    j3_sent = summary.j3_sent,
                    j7_sent = summary.j7_sent,
                    "quote_relance_dispatch: passe terminée"
                );
            }
            Ok(_) => {}
            Err(err) => {
                tracing::error!(error = ?err, "quote_relance_dispatch: passe en échec");
            }
        }
    }
}
