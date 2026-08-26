//! `GET /v1/cabinet/payouts` — rapprochement virements Stripe/GoCardless
//! vs paiements internes (#4129).
//!
//! Quoi : aucun écran ne permettait de vérifier qu'un virement Stripe/
//! GoCardless reçu sur le compte bancaire du cabinet correspond bien à la
//! somme des paiements internes correspondants (le rapprochement à 70%
//! automatisé revendiqué par Desmos n'avait aucun équivalent, même
//! manuel).
//!
//! Pourquoi un MOCK plutôt qu'un vrai appel API : aucun compte Stripe
//! Connect / GoCardless (avec accès à l'API Payouts) n'est actuellement
//! configuré pour ce projet (cf. `docs/14-decision-terminal-paiement-cb.md`
//! §2 — même constat pour Stripe côté paiement en ligne : aucun appel
//! réseau vers `api.stripe.com` n'existe dans ce backend). Construire cet
//! écran contre un client HTTP réel et non testable serait un travail
//! spéculatif. Ce module retourne des payouts **au format réel** des deux
//! providers (mêmes noms de champs que leurs API Payouts officielles —
//! Stripe : `id`/`amount`/`currency`/`arrival_date`/`status` ; GoCardless :
//! `id`/`amount`/`currency`/`reference`/`status`) pour que l'écran soit
//! compréhensible et directement remplaçable par un vrai client HTTP plus
//! tard (même contrat de sortie, `PayoutView`, à l'exception de
//! `internal_payments`, propre à cet écran).
//!
//! Rapprochement : pour chaque payout mock, on calcule la somme des
//! `payment.amount` internes (`status='paid'`, `provider` correspondant,
//! `paid_at` le même jour que `arrival_date`) et on compare au montant du
//! payout — `reconciled` si égal, `to_verify` sinon. Un des payouts mock
//! est délibérément non-rapprochable (montant fixe ne correspondant à
//! aucune somme réaliste) pour que l'écran démontre les deux états sans
//! dépendre des données déjà présentes dans le cabinet.
//!
//! Modes d'échec : aucun (données mock, pas d'appel externe qui pourrait
//! échouer) — seule la requête SQL de somme interne peut échouer → 500.
//!
//! Note déploiement (#4734) : ce module a été mergé (PR #4569, commit
//! 04e804ed) mais le run `deploy.yml` déclenché juste après (id 24952) a
//! échoué, laissant la route absente du binaire live pendant plusieurs
//! heures malgré un code strictement correct (deploy-lag pur, cf. registre
//! `qa/explored-paths.md`). Ce commit re-déclenche un déploiement frais sur
//! `main` (le fichier n'est pas dans `paths-ignore` de `deploy.yml`) pour
//! que le prochain run `deploy` publie enfin cette route.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct PayoutsQuery {
    /// `stripe` ou `gocardless`. Absent -> les deux providers combinés.
    pub provider: Option<String>,
}

#[derive(Serialize)]
pub struct PayoutView {
    pub id: String,
    pub provider: &'static str,
    /// Centimes, comme `payment.amount` côté interne (converti pour la
    /// comparaison — les API réelles Stripe/GoCardless expriment aussi
    /// leurs montants en unité mineure, ex. centimes pour EUR).
    pub amount_cents: i64,
    pub currency: &'static str,
    pub arrival_date: String,
    /// Statut natif du provider — toujours `"paid"` pour ce mock (un
    /// payout non finalisé n'aurait pas encore de virement à rapprocher).
    pub provider_status: &'static str,
    /// `reconciled` | `to_verify` — calculé par ce backend, absent des API
    /// réelles Stripe/GoCardless (c'est la valeur ajoutée de cet écran).
    pub reconciliation_status: &'static str,
    /// Somme des paiements internes trouvés pour ce jour/provider — permet
    /// à l'UI d'expliquer l'écart plutôt que de juste afficher "à vérifier".
    pub internal_payments_total_cents: i64,
    /// Chaque paiement interne (`payment`, tous canaux) enregistré ce
    /// jour-là pour le cabinet — liste « Paiements internes du jour »
    /// (#5109). Contrairement à `internal_payments_total_cents`, non filtré
    /// par provider : inclut aussi les règlements espèces/chèque/virement
    /// (`provider='manual'`), qui ne transitent jamais par Stripe/GoCardless.
    pub internal_payments: Vec<InternalPaymentView>,
}

#[derive(Serialize)]
pub struct InternalPaymentView {
    pub patient_name: String,
    /// Heure `HH:mm` de l'encaissement (`payment.paid_at`).
    pub time: String,
    pub amount_cents: i64,
    /// Libellé FR du canal (ex. « Carte », « Espèces ») — dérivé de
    /// `payment.method`.
    pub method_label: &'static str,
    /// `false` pour les canaux physiques (espèces, chèque, virement) qui ne
    /// transitent jamais par le prestataire Stripe/GoCardless — affiché
    /// comme « non rapprochable » côté UI.
    pub reconcilable_by_provider: bool,
}

/// Libellé FR + rapprochabilité par le prestataire pour un `payment.method`.
fn describe_method(method: &str) -> (&'static str, bool) {
    match method {
        "card" => ("Carte", true),
        "apple_pay" => ("Apple Pay", true),
        "google_pay" => ("Google Pay", true),
        "sepa" => ("SEPA", true),
        "cash" => ("Espèces", false),
        "check" => ("Chèque", false),
        "bank_transfer" => ("Virement", false),
        _ => ("Autre", false),
    }
}

#[derive(Serialize)]
pub struct PayoutsResponse {
    pub data: Vec<PayoutView>,
}

struct MockPayout {
    id: &'static str,
    provider: &'static str,
    amount_cents: i64,
    arrival_date: &'static str,
}

/// Jeu de payouts mock — deux jours plausibles (à faire correspondre à des
/// paiements internes existants pour un rendu réaliste en démo) + un
/// dernier délibérément non rapprochable.
const MOCK_PAYOUTS: &[MockPayout] = &[
    MockPayout {
        id: "po_mock_1a2b3c",
        provider: "stripe",
        amount_cents: 15_000,
        arrival_date: "2026-07-28",
    },
    MockPayout {
        id: "PO-MOCK-9F8E7D",
        provider: "gocardless",
        amount_cents: 8_500,
        arrival_date: "2026-07-29",
    },
    // Montant fixe arbitraire, ne correspond à aucune somme réaliste de
    // paiements internes — démontre volontairement l'état "à vérifier".
    MockPayout {
        id: "po_mock_unmatched",
        provider: "stripe",
        amount_cents: 999_999,
        arrival_date: "2026-07-30",
    },
];

/// `GET /v1/cabinet/payouts` — liste les payouts (mock, cf. docstring du
/// module) rapprochés contre les paiements internes du cabinet courant.
pub async fn list_payouts(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(query): Query<PayoutsQuery>,
) -> Result<Json<PayoutsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Rapprochements manuels persistés (#5969) : une fois marqué "rapproché"
    // par le secrétariat, le statut ne doit plus jamais régresser au simple
    // recalcul mock, y compris après un refresh/redéploiement.
    let reconciled_rows = sqlx::query(
        "SELECT payout_id FROM cabinet_payout_action \
         WHERE cabinet_id = $1 AND action = 'reconciled'",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let manually_reconciled: std::collections::HashSet<String> = reconciled_rows
        .iter()
        .map(|r| r.try_get::<String, _>("payout_id"))
        .collect::<Result<_, _>>()
        .map_err(|_| AppError::Internal)?;

    let mut data = Vec::new();
    for payout in MOCK_PAYOUTS {
        if let Some(filter) = query.provider.as_deref() {
            if filter != payout.provider {
                continue;
            }
        }

        let row = sqlx::query(
            "SELECT COALESCE(SUM(amount) * 100, 0)::bigint AS total_cents \
             FROM payment \
             WHERE cabinet_id = $1 AND provider = $2 AND status = 'paid' \
               AND paid_at::date = $3::date",
        )
        .bind(claims.cabinet_id)
        .bind(payout.provider)
        .bind(payout.arrival_date)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let internal_total: i64 = row.try_get("total_cents").map_err(|_| AppError::Internal)?;

        let reconciliation_status = if internal_total == payout.amount_cents
            || manually_reconciled.contains(payout.id)
        {
            "reconciled"
        } else {
            "to_verify"
        };

        // Liste « Paiements internes du jour » (#5109) : tous les canaux
        // (pas seulement `payout.provider`, contrairement au total ci-dessus)
        // pour que l'écart affiché à l'écran s'explique par des règlements
        // physiques (espèces/chèque) qui ne transitent jamais par le
        // prestataire.
        let payment_rows = sqlx::query(
            "SELECT p.first_name || ' ' || p.last_name AS patient_name, \
                    pay.method, \
                    (pay.amount * 100)::bigint AS amount_cents, \
                    to_char(pay.paid_at, 'HH24:MI') AS paid_at_time \
             FROM payment pay \
             JOIN patient p ON p.id = pay.patient_id \
             WHERE pay.cabinet_id = $1 AND pay.status = 'paid' \
               AND pay.method IS NOT NULL AND pay.paid_at::date = $2::date \
             ORDER BY pay.paid_at ASC",
        )
        .bind(claims.cabinet_id)
        .bind(payout.arrival_date)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let mut internal_payments = Vec::with_capacity(payment_rows.len());
        for prow in &payment_rows {
            let patient_name: String = prow
                .try_get("patient_name")
                .map_err(|_| AppError::Internal)?;
            let method: String = prow.try_get("method").map_err(|_| AppError::Internal)?;
            let amount_cents: i64 = prow
                .try_get("amount_cents")
                .map_err(|_| AppError::Internal)?;
            let time: String = prow
                .try_get("paid_at_time")
                .map_err(|_| AppError::Internal)?;
            let (method_label, reconcilable_by_provider) = describe_method(&method);
            internal_payments.push(InternalPaymentView {
                patient_name,
                time,
                amount_cents,
                method_label,
                reconcilable_by_provider,
            });
        }

        data.push(PayoutView {
            id: payout.id.to_string(),
            provider: payout.provider,
            amount_cents: payout.amount_cents,
            currency: "EUR",
            arrival_date: payout.arrival_date.to_string(),
            provider_status: "paid",
            reconciliation_status,
            internal_payments_total_cents: internal_total,
            internal_payments,
        });
    }

    Ok(Json(PayoutsResponse { data }))
}

/// Enregistre une action humaine (`reconciled` ou `flagged_to_accountant`)
/// sur un payout mock — idempotent (`ON CONFLICT DO NOTHING`, cf. migration
/// 0237). `404` si `payout_id` ne correspond à aucun mock connu.
async fn record_payout_action(
    state: &AppState,
    claims: &ProSecretaryPlusClaims,
    payout_id: &str,
    action: &str,
) -> Result<(), AppError> {
    if !MOCK_PAYOUTS.iter().any(|p| p.id == payout_id) {
        return Err(AppError::NotFound);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO cabinet_payout_action (cabinet_id, payout_id, action, created_by) \
         VALUES ($1, $2, $3, $4) \
         ON CONFLICT (cabinet_id, payout_id, action) DO NOTHING",
    )
    .bind(claims.cabinet_id)
    .bind(payout_id)
    .bind(action)
    .bind(claims.sub)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(())
}

/// `POST /v1/cabinet/payouts/:id/reconcile` — marque le virement comme
/// rapproché (décision humaine, #5969). Persisté : survit à un refresh,
/// contrairement à l'ancienne mutation purement locale côté Flutter.
pub async fn reconcile_payout(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(payout_id): Path<String>,
) -> Result<StatusCode, AppError> {
    record_payout_action(&state, &claims, &payout_id, "reconciled").await?;
    Ok(StatusCode::NO_CONTENT)
}

/// `POST /v1/cabinet/payouts/:id/flag-accountant` — signale l'écart au
/// comptable (#5969). Aucun système de notification/email disponible pour
/// ce mock (cf. docstring module) : la trace DB fait office d'alerte —
/// remplace l'ancien handler vide qui ne faisait strictement rien.
pub async fn flag_payout_to_accountant(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(payout_id): Path<String>,
) -> Result<StatusCode, AppError> {
    record_payout_action(&state, &claims, &payout_id, "flagged_to_accountant").await?;
    Ok(StatusCode::NO_CONTENT)
}
