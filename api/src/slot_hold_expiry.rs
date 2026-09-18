//! Reaper des holds de créneau expirés — #6992 / #6840.
//!
//! Quoi : `POST /v1/slots/:id/hold` (`marketplace::hold_slot`) pose un hold
//! de 10 min (`slot_holds.expires_at`, migration 0255/0256) et passe le
//! créneau en `status='held'`. Rien ne purgeait `slot_holds` à `expires_at` :
//! la seule libération existante était PARESSEUSE, interne à
//! `claim_and_hold_slot` (migration 0141, #3606), donc atteignable uniquement
//! par un nouveau `POST /v1/slots/:id/hold` sur ce créneau précis — or les
//! listings publics (`/v1/search/slots`, `/v1/providers/:id/availability`)
//! filtraient `status = 'open'` sans jamais consulter `slot_holds.expires_at`.
//! Un tunnel abandonné (cas nominal : onglet fermé, retour arrière,
//! hésitation > 10 min) retirait donc le créneau du catalogue POUR DE BON :
//! invisible, il n'était plus jamais candidat au hold qui, seul, l'aurait
//! libéré. Le stock de créneaux en ligne fondait silencieusement.
//!
//! Correction en deux volets, complémentaires :
//! 1. Chemin de lecture (`marketplace.rs`, `SLOT_BOOKABLE_CLAUSE`) : un
//!    créneau `held` dont le hold est expiré est traité comme `open` DANS LA
//!    REQUÊTE (`slot_hold_expired(sl.id)`, migration 0272) — correct dès la
//!    première seconde après `expires_at`, sans dépendre du passage du reaper.
//! 2. Ce module : boucle périodique `tokio::spawn` dans le même binaire, même
//!    pattern que `reminder_dispatch.rs` / `quote_relance_dispatch.rs` /
//!    `visit_offer_expiry.rs` (pas de job queue apalis dans ce dépôt), qui
//!    appelle `release_expired_slot_holds()` (SECURITY DEFINER, migration
//!    0272) pour purger les holds expirés et repasser les créneaux en `open`
//!    — l'état en base redevient cohérent (agenda cabinet, interop FHIR Slot
//!    `busy-tentative`, etc.) au lieu de rester `held` à vie.
//!
//! Pourquoi une fonction SQL SECURITY DEFINER et non un `DELETE` direct :
//! `slot_holds` est sous `FORCE ROW LEVEL SECURITY` avec une policy scopée
//! sur `app.current_cabinet_id` (migration 0110) — un worker hors contexte de
//! requête HTTP n'a aucun GUC cabinet, un `DELETE` direct sous `nubia_app`
//! ne toucherait donc jamais aucune ligne (fail-closed). Même besoin de
//! contournement que `due_reminders_for_dispatch` (0156) ou
//! `expire_stale_visit_offers` (0236).

use sqlx::PgPool;

use crate::auth::AppError;

/// Résumé d'une passe du reaper (logs et tests).
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct SlotHoldExpirySummary {
    /// Nombre de holds expirés purgés (et de créneaux repassés `open`).
    pub released: u32,
}

/// Erreur d'une passe du reaper — type dédié (pas `AppError`), même
/// convention que `ReminderDispatchError`/`VisitOfferExpiryError`.
#[derive(Debug)]
pub struct SlotHoldExpiryError(String);

impl std::fmt::Display for SlotHoldExpiryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "slot hold expiry error: {}", self.0)
    }
}

impl std::error::Error for SlotHoldExpiryError {}

impl From<AppError> for SlotHoldExpiryError {
    fn from(err: AppError) -> Self {
        Self(format!("{err:?}"))
    }
}

/// Purge les holds dont `expires_at <= now()` et repasse en `open` les
/// créneaux correspondants encore `held` (`release_expired_slot_holds()`,
/// migration 0272). Idempotent : une passe sans hold expiré est un no-op.
pub async fn dispatch_slot_hold_expiry(
    db: &PgPool,
) -> Result<SlotHoldExpirySummary, SlotHoldExpiryError> {
    let released: i32 = sqlx::query_scalar("SELECT release_expired_slot_holds()")
        .fetch_one(db)
        .await
        .map_err(|_| AppError::Internal)?;
    Ok(SlotHoldExpirySummary {
        released: u32::try_from(released).unwrap_or_default(),
    })
}

/// Boucle périodique appelée depuis `main.rs` (`tokio::spawn`, cf. doc de
/// module). Tourne indéfiniment ; une erreur de passe est loguée, jamais fatale.
pub async fn run_slot_hold_expiry_loop(db: PgPool, interval: std::time::Duration) {
    let mut ticker = tokio::time::interval(interval);
    loop {
        ticker.tick().await;
        match dispatch_slot_hold_expiry(&db).await {
            Ok(summary) if summary.released > 0 => {
                tracing::info!(
                    released = summary.released,
                    "slot_hold_expiry: passe terminée"
                );
            }
            Ok(_) => {}
            Err(err) => {
                tracing::error!(error = ?err, "slot_hold_expiry: passe en échec");
            }
        }
    }
}
