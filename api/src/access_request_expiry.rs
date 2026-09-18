//! Expiration des demandes d'accès « proche adulte » sans réponse — #7296.
//!
//! Quoi : la maquette de référence (`design/mockups/v2/Patient Invitation
//! proche adulte.html`, note 6 « Une demande expire ») promet, et l'app
//! affiche (`dependents_page.dart`, `_ExpiryNotice`) : « Une demande sans
//! réponse expire au bout de 30 jours. Vous pourrez en envoyer une
//! nouvelle. » Le statut `expiree` est prévu par le schéma depuis l'origine
//! (`account_access_request.status` CHECK, migration 0241) et déjà rendu par
//! le front (`AccessRequestStatus.expiree`), mais rien ne l'écrivait jamais :
//! une demande `envoyee` restait acceptable indéfiniment, et l'anti-doublon
//! de `POST /v1/account/access-requests` (`status IN ('envoyee',
//! 'acceptee')`) bloquait toute ré-invitation pour de bon.
//!
//! Quand : boucle périodique `tokio::spawn` dans le même binaire, même
//! pattern que `quote_relance_dispatch.rs`/`visit_offer_expiry.rs`/
//! `slot_hold_expiry.rs` (pas de job apalis dans ce dépôt à ce jour).
//!
//! Pourquoi une simple `UPDATE` sans fonction SQL `SECURITY DEFINER`
//! (contrairement à `slot_hold_expiry.rs`) : `account_access_request` a une
//! policy RLS ouverte pour `nubia_app` (`access_request_app_all`, `USING
//! (true)`, migration 0241) — le filtrage est déjà applicatif, pas besoin de
//! contourner une policy scopée cabinet/compte pour un worker hors contexte
//! de requête.
//!
//! Effet de bord attendu : passer `envoyee` -> `expiree` fait sortir la
//! demande de `status IN ('envoyee', 'acceptee')`, donc de l'anti-doublon
//! (`post_account_access_requests`, `auth/mod.rs`) — la seconde moitié de la
//! promesse (« vous pourrez en envoyer une nouvelle ») se résout sans
//! changement supplémentaire côté anti-doublon.

use sqlx::PgPool;

use crate::auth::AppError;

/// Délai au-delà duquel une demande `envoyee` sans décision expire —
/// maquette de référence, note 6 « Une demande expire : trente jours ».
const ACCESS_REQUEST_EXPIRY_DAYS: i64 = 30;

/// Résumé d'une passe d'expiration (logs/tests).
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct AccessRequestExpirySummary {
    pub expired: u32,
}

/// Erreur d'une passe d'expiration — type dédié (pas `AppError`), même
/// convention que `QuoteRelanceDispatchError`/`SlotHoldExpiryError`.
#[derive(Debug)]
pub struct AccessRequestExpiryError(String);

impl std::fmt::Display for AccessRequestExpiryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "access request expiry error: {}", self.0)
    }
}

impl std::error::Error for AccessRequestExpiryError {}

impl From<AppError> for AccessRequestExpiryError {
    fn from(err: AppError) -> Self {
        Self(format!("{err:?}"))
    }
}

/// Passe `envoyee` -> `expiree` toute demande non décidée/annulée dont
/// `sent_at` remonte à ≥30 jours. Idempotent : une passe sans demande due est
/// un no-op.
pub async fn dispatch_access_request_expiry(
    db: &PgPool,
) -> Result<AccessRequestExpirySummary, AccessRequestExpiryError> {
    let result = sqlx::query(&format!(
        "UPDATE account_access_request \
         SET status = 'expiree', updated_at = now() \
         WHERE status = 'envoyee' AND cancelled_at IS NULL \
           AND sent_at <= now() - interval '{ACCESS_REQUEST_EXPIRY_DAYS} days'"
    ))
    .execute(db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(AccessRequestExpirySummary {
        expired: u32::try_from(result.rows_affected()).unwrap_or_default(),
    })
}

/// Boucle périodique appelée depuis `main.rs` (`tokio::spawn`, cf. doc de
/// module). Tourne indéfiniment ; une erreur de passe est loguée, jamais
/// fatale.
pub async fn run_access_request_expiry_loop(db: PgPool, interval: std::time::Duration) {
    let mut ticker = tokio::time::interval(interval);
    loop {
        ticker.tick().await;
        match dispatch_access_request_expiry(&db).await {
            Ok(summary) if summary.expired > 0 => {
                tracing::info!(
                    expired = summary.expired,
                    "access_request_expiry: passe terminée"
                );
            }
            Ok(_) => {}
            Err(err) => {
                tracing::error!(error = ?err, "access_request_expiry: passe en échec");
            }
        }
    }
}
