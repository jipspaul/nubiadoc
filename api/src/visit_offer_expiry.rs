//! Résolution des demandes de visite infirmière dont la dernière offre a été
//! déclinée ou a expiré sans réponse — #5730 — et de celles n'ayant jamais eu
//! d'offre faute d'infirmière en ligne au moment de la création — #6450.
//!
//! Quoi : avant #5730, `visit_request.status` restait bloqué à `offered`
//! indéfiniment dès que l'infirmière déclinait sa seule offre en cours (ou ne
//! répondait jamais avant `visit_offer.expires_at`) — aucun signal au patient,
//! seule sortie : annuler manuellement. `settle_visit_request_offers`
//! (SECURITY DEFINER, migration 0236) résout la demande : re-fanout vers
//! d'autres infirmières proches en ligne si disponibles, sinon passage à
//! `expired` (déjà permis par le CHECK de 0234, jamais atteint auparavant).
//! #6450 : le même trou existait pour `requested` — le fan-out n'a lieu qu'à
//! la création (`api/src/nurse/requests.rs`) ; si aucune infirmière n'est en
//! ligne à cet instant, rien ne retente jamais, même quand une infirmière
//! proche repasse en ligne. `settle_unmatched_visit_request`/
//! `expire_stale_visit_requests` (migration 0251) appliquent le même remède à
//! cette branche, réutilisant [`apply_settlement`] tel quel (mêmes outcomes
//! `reoffered`/`expired`).
//!
//! Points d'entrée pour ces résolutions, tous SQL (migrations 0236 et 0251) —
//! ce module ne fait qu'en tirer les conséquences applicatives (notifier) :
//! - `decline_visit_offer` (redéfinie en 0236) décline puis résout
//!   ATOMIQUEMENT dans le même appel SQL — `nurse::visits::decline_offer`
//!   n'a plus qu'à lire le résultat et appeler [`apply_settlement`] pour les
//!   notifications. Volontairement découplé : si la notification échoue, le
//!   déclin + sa résolution sont déjà commités en base (pas de risque de
//!   revenir au bug #5730 sur un simple aléa de notification).
//! - [`run_visit_offer_expiry_loop`] : boucle périodique `tokio::spawn` dans
//!   le même binaire, même pattern que `reminder_dispatch.rs`/
//!   `quote_relance_dispatch.rs` (pas de job apalis dans ce dépôt à ce jour)
//!   — seul filet pour le cas où l'infirmière ne répond jamais (ni accept ni
//!   decline) avant l'expiration du TTL de son offre (et filet générique pour
//!   toute demande `offered` sans offre pending restante, cf.
//!   `expire_stale_visit_offers`) ; c'est aussi elle qui retente/expire les
//!   demandes `requested` sans offre (`expire_stale_visit_requests`, #6450).
//!
//! Pourquoi pas de publication WS depuis la boucle périodique : contrairement
//! au handler `decline_offer` (qui reçoit le `WsHub` de la requête HTTP en
//! cours via `Extension`), la boucle tourne hors de tout contexte de requête
//! et n'a pas accès à l'instance `WsHub` du routeur (même limite déjà
//! implicite dans `reminder_dispatch.rs`/`quote_relance_dispatch.rs`, qui ne
//! publient pas non plus sur le WS). Le patient/l'infirmière reçoivent tout
//! de même la notification in-app + push ; le WS live-update est un bonus
//! propre au chemin synchrone.

use sqlx::postgres::PgRow;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::auth::AppError;
use crate::{notify, realtime::WsHub, JobDispatcher};

/// Résumé d'une passe d'expiration (logs).
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct VisitOfferExpirySummary {
    pub reoffered: u32,
    pub expired: u32,
}

/// Erreur d'une passe d'expiration — type dédié (pas `AppError`), même
/// convention que `ReminderDispatchError`/`QuoteRelanceDispatchError`.
#[derive(Debug)]
pub struct VisitOfferExpiryError(String);

impl std::fmt::Display for VisitOfferExpiryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "visit offer expiry error: {}", self.0)
    }
}

impl std::error::Error for VisitOfferExpiryError {}

impl From<AppError> for VisitOfferExpiryError {
    fn from(err: AppError) -> Self {
        Self(format!("{err:?}"))
    }
}

/// Applique les effets de bord d'une résolution déjà commitée en SQL (retour
/// de `settle_visit_request_offers`/`decline_visit_offer`/
/// `expire_stale_visit_offers`, migration 0236) : notifie les nouvelles
/// infirmières sollicitées (`reoffered`, `new_nurse_ids` non vide) ou le
/// patient (`expired`). No-op pour tout autre `outcome` (`offered` : offre
/// pending encore valide ; `noop`/`not_found` : demande déjà résolue par un
/// appel concurrent ou inexistante).
///
/// `new_nurse_ids`/`patient_account_id` viennent directement du retour SQL
/// (SECURITY DEFINER) plutôt que d'une relecture de `visit_offer`/
/// `visit_request` par ce module : ces deux tables sont sous RLS FORCE côté
/// `nubia_app`, scopée au GUC du tenant patient/infirmière courant — un GUC
/// qu'un worker périodique hors contexte de requête HTTP n'a aucune raison
/// de connaître.
pub(crate) async fn apply_settlement(
    db: &PgPool,
    hub: Option<&WsHub>,
    dispatcher: &dyn JobDispatcher,
    request_id: Uuid,
    outcome: &str,
    new_nurse_ids: &[Uuid],
    patient_account_id: Option<Uuid>,
) -> Result<(), AppError> {
    match outcome {
        "reoffered" => {
            let mut tx = db.begin().await.map_err(|_| AppError::Internal)?;
            let mut nurse_notifs: Vec<(Uuid, Uuid)> = Vec::new();
            for nurse_id in new_nurse_ids {
                let staff = notify::notify_nurse_staff(
                    &mut tx,
                    *nurse_id,
                    "visit_offer",
                    "Nouvelle demande de visite proche",
                    serde_json::json!({ "visit_request_id": request_id }),
                )
                .await?;
                nurse_notifs.extend(staff);
            }
            tx.commit().await.map_err(|_| AppError::Internal)?;

            for (app_user_id, notification_id) in nurse_notifs {
                dispatcher.enqueue_push_notification(app_user_id, notification_id);
            }
            if let Some(hub) = hub {
                for nurse_id in new_nurse_ids {
                    hub.publish_named(
                        &format!("nurse_offers:{nurse_id}"),
                        notify::order_event(
                            &format!("nurse_offers:{nurse_id}"),
                            request_id,
                            "offered",
                        ),
                    );
                }
            }
        }
        "expired" => {
            let Some(patient_account_id) = patient_account_id else {
                return Ok(());
            };
            let mut tx = db.begin().await.map_err(|_| AppError::Internal)?;
            let pushed = notify::notify_patient_account(
                &mut tx,
                patient_account_id,
                "visit_request_expired",
                "Aucune infirmière disponible actuellement",
                serde_json::json!({ "visit_request_id": request_id }),
            )
            .await?;
            tx.commit().await.map_err(|_| AppError::Internal)?;

            if let Some((app_user_id, notification_id)) = pushed {
                dispatcher.enqueue_push_notification(app_user_id, notification_id);
            }
        }
        _ => {}
    }
    Ok(())
}

/// Applique [`apply_settlement`] à chaque ligne renvoyée par l'une des deux
/// fonctions de découverte SQL (`expire_stale_visit_offers`/
/// `expire_stale_visit_requests`, même forme de retour), en accumulant dans
/// `summary`. Ne panique jamais sur une demande individuelle en erreur : le
/// balayage continue.
///
/// La résolution SQL a déjà committé au moment où [`apply_settlement`]
/// s'exécute pour chaque ligne — une erreur ici (typiquement
/// `notify_nurse_staff`/`notify_patient_account`) ne remet PAS la demande en
/// jeu : elle est déjà sortie de son statut d'origine, donc ne réapparaîtra
/// plus jamais dans un passage suivant. Seule la notification applicative
/// (in-app/push) peut être perdue sur cet aléa, pas la résolution elle-même
/// (déjà garantie par le passage SQL qui précède).
async fn settle_rows(
    db: &PgPool,
    dispatcher: &dyn JobDispatcher,
    rows: Vec<PgRow>,
    summary: &mut VisitOfferExpirySummary,
) -> Result<(), VisitOfferExpiryError> {
    for row in rows {
        let request_id: Uuid = row
            .try_get("visit_request_id")
            .map_err(|_| AppError::Internal)?;
        let outcome: String = row.try_get("outcome").map_err(|_| AppError::Internal)?;
        let new_nurse_ids: Option<Vec<Uuid>> = row
            .try_get("new_nurse_ids")
            .map_err(|_| AppError::Internal)?;
        let patient_account_id: Option<Uuid> = row
            .try_get("patient_account_id")
            .map_err(|_| AppError::Internal)?;

        match apply_settlement(
            db,
            None,
            dispatcher,
            request_id,
            &outcome,
            new_nurse_ids.as_deref().unwrap_or_default(),
            patient_account_id,
        )
        .await
        {
            Ok(()) => match outcome.as_str() {
                "reoffered" => summary.reoffered += 1,
                "expired" => summary.expired += 1,
                _ => {}
            },
            Err(err) => {
                tracing::warn!(
                    visit_request_id = %request_id,
                    error = ?err,
                    "visit_offer_expiry: échec traitement (sans interrompre le balayage)"
                );
            }
        }
    }
    Ok(())
}

/// Marque expirées les offres pending dont le TTL est dépassé (infirmière
/// n'ayant jamais répondu) et retente/expire les demandes `requested` sans
/// offre (#6450), puis résout chaque demande concernée via [`settle_rows`].
pub async fn dispatch_visit_offer_expiry(
    db: &PgPool,
    dispatcher: &dyn JobDispatcher,
) -> Result<VisitOfferExpirySummary, VisitOfferExpiryError> {
    let stale_offers = sqlx::query(
        "SELECT visit_request_id, outcome, new_nurse_ids, patient_account_id \
         FROM expire_stale_visit_offers()",
    )
    .fetch_all(db)
    .await
    .map_err(|_| AppError::Internal)?;

    let stale_requests = sqlx::query(
        "SELECT visit_request_id, outcome, new_nurse_ids, patient_account_id \
         FROM expire_stale_visit_requests()",
    )
    .fetch_all(db)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut summary = VisitOfferExpirySummary::default();
    settle_rows(db, dispatcher, stale_offers, &mut summary).await?;
    settle_rows(db, dispatcher, stale_requests, &mut summary).await?;
    Ok(summary)
}

/// Boucle périodique appelée depuis `main.rs` (`tokio::spawn`, cf. doc de
/// module). Tourne indéfiniment ; une erreur de passe est loguée, jamais fatale.
pub async fn run_visit_offer_expiry_loop(
    db: PgPool,
    dispatcher: std::sync::Arc<dyn JobDispatcher>,
    interval: std::time::Duration,
) {
    let mut ticker = tokio::time::interval(interval);
    loop {
        ticker.tick().await;
        match dispatch_visit_offer_expiry(&db, dispatcher.as_ref()).await {
            Ok(summary) if summary.reoffered > 0 || summary.expired > 0 => {
                tracing::info!(
                    reoffered = summary.reoffered,
                    expired = summary.expired,
                    "visit_offer_expiry: passe terminée"
                );
            }
            Ok(_) => {}
            Err(err) => {
                tracing::error!(error = ?err, "visit_offer_expiry: passe en échec");
            }
        }
    }
}
