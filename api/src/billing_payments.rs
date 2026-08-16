//! Handlers `POST /v1/payments/intent` et `POST /v1/pharmacy/quotes/:id/payment-intent`
//! — création de PaymentIntent Stripe.
//!
//! Extrait de `billing.rs` (refactor de taille, #4056 / CLAUDE.md plafond
//! 700 lignes) — module autonome, mêmes handlers/contrats, aucun changement
//! fonctionnel. `billing.rs` délègue à `create_payment_intent` pour l'alias
//! patient BR5 `POST /v1/billing/quotes/:id/deposit`.

use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    reviews::is_unique_violation,
    AppState,
};

/// Nom de la contrainte/index UNIQUE violée par une erreur `23505`, `None` si
/// l'erreur n'est pas une violation d'unicité. #4418 : `payment` porte deux
/// contraintes UNIQUE distinctes pouvant se déclencher sur le même INSERT
/// (`payment_idempotency_key_unique`, `payment_pharmacy_quote_pending_unique`)
/// — il faut discriminer par nom pour mapper chacune vers la bonne réponse.
fn unique_violation_constraint(e: &sqlx::Error) -> Option<String> {
    match e {
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23505") => {
            db_err.constraint().map(str::to_string)
        }
        _ => None,
    }
}

/// Corps de `POST /v1/payments/intent`.
#[derive(Deserialize)]
pub struct PaymentIntentBody {
    pub quote_id: Uuid,
    pub kind: String,
    pub amount_cents: i64,
    pub method: String,
}

/// Réponse de `POST /v1/payments/intent`.
#[derive(Serialize)]
pub struct PaymentIntentResponse {
    pub payment_id: Uuid,
    pub client_secret: String,
}

/// `POST /v1/payments/intent` — crée un PaymentIntent Stripe pour le patient.
///
/// Token `kind:"patient"` requis ; token pro → `403`.
/// Header `Idempotency-Key` obligatoire → `422` si absent.
/// Le devis (`quote_id`) doit être dans l'état `signed` → `409` sinon.
/// Idempotence : même clé sur un paiement existant → `201` avec le même `client_secret`.
/// Le cache `idempotency_keys` a un TTL de 24h ; passé ce délai, la contrainte
/// UNIQUE `payment_idempotency_key_unique` (permanente, elle) sur `payment.idempotency_key`
/// peut encore détecter une clé déjà utilisée → `409 idempotency_key_conflict`
/// (jamais un `500`, l'empreinte d'origine n'étant plus vérifiable, cf. #3867).
/// PCI délégué (§07 §6.1) : seul le `client_secret` est transmis, aucune donnée carte.
/// Confirmation finale par webhook Stripe (statut `pending` → `paid`).
pub async fn create_payment_intent(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    headers: HeaderMap,
    Json(body): Json<PaymentIntentBody>,
) -> Result<(StatusCode, Json<PaymentIntentResponse>), AppError> {
    let idempotency_key = headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty())
        .ok_or(AppError::ValidationError)?
        .to_owned();

    if !["deposit", "installment", "full"].contains(&body.kind.as_str()) {
        return Err(AppError::ValidationError);
    }
    if !["card", "apple_pay", "google_pay", "sepa"].contains(&body.method.as_str()) {
        return Err(AppError::ValidationError);
    }
    if body.amount_cents <= 0 {
        return Err(AppError::ValidationError);
    }

    // Empreinte de la requête : une même clé rejouée avec un compte/devis/montant
    // différent ne doit jamais renvoyer le paiement d'une autre requête (#3547).
    let fingerprint = format!(
        "account={}|quote={}|kind={}|amount={}|method={}",
        claims.account_id, body.quote_id, body.kind, body.amount_cents, body.method
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Idempotence : check idempotency_keys avant tout travail tenant-scoped (TTL 24h).
    let cached = sqlx::query(
        "SELECT response, fingerprint FROM idempotency_keys \
         WHERE key = $1 AND created_at > now() - interval '24 hours'",
    )
    .bind(&idempotency_key)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(cached_row) = cached {
        let cached_fingerprint: String = cached_row
            .try_get("fingerprint")
            .map_err(|_| AppError::Internal)?;
        if cached_fingerprint != fingerprint {
            tx.commit().await.map_err(|_| AppError::Internal)?;
            tracing::warn!(
                account_id = %claims.account_id,
                "idempotency key replayed with a different fingerprint"
            );
            return Err(AppError::IdempotencyKeyConflict);
        }
        let resp: serde_json::Value = cached_row
            .try_get("response")
            .map_err(|_| AppError::Internal)?;
        let payment_id: Uuid = resp["payment_id"]
            .as_str()
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or(AppError::Internal)?;
        let client_secret: String = resp["client_secret"]
            .as_str()
            .map(|s| s.to_owned())
            .ok_or(AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        tracing::info!(
            account_id = %claims.account_id,
            payment_id = %payment_id,
            "payment intent idempotent replay"
        );
        return Ok((
            StatusCode::CREATED,
            Json(PaymentIntentResponse {
                payment_id,
                client_secret,
            }),
        ));
    }

    // Scope patient pour lire le devis via la policy quote_patient_read (migration 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Lecture non verrouillée pour résoudre cabinet_id : la policy RLS
    // `quote_patient_read` (permissive, scope app.patient_account_id) suffit
    // ici. On ne peut pas encore poser FOR UPDATE (cf. plus bas) car le GUC
    // cabinet, requis par la policy tenant_isolation (SELECT+UPDATE) que
    // Postgres exige aussi sous FOR UPDATE, n'est positionné qu'après avoir
    // lu cabinet_id — donc un premier FOR UPDATE ici renverrait toujours 0
    // ligne (régression #3775 : le correctif avait rendu POST /payments/intent
    // 404 sur CHAQUE appel, pas seulement en cas de course concurrente).
    // #4515 : patient_share_cents ne peut PAS être calculé dans cette même
    // requête — `quote_item` est en FORCE RLS avec la seule policy
    // `tenant_isolation` (scope app.current_cabinet_id, pas encore posé ici) ;
    // aucune policy patient permissive n'existe sur `quote_item` (contrairement
    // à `quote`, cf. migration 0029). Une sous-requête sur quote_item à ce
    // stade voit toujours 0 ligne → patient_share_cents = 0 → tout paiement
    // rejeté en 422 (régression #4433, qui avait introduit ce calcul sans
    // anticiper la dépendance RLS de quote_item au GUC cabinet).
    // Ownership (patient OU compte facturé billed_to_account_id, #4098) déjà posée
    // par la policy RLS quote_patient_read (migration 0175) via le GUC
    // app.patient_account_id ci-dessus — pas de JOIN patient ici : la table
    // `patient` a sa propre policy RLS `patient_account_read` (migration 0029,
    // scope strict patient_account_id = app.patient_account_id, aucune branche
    // tutelle), donc un JOIN patient éliminerait la ligne du dépendant AVANT que
    // la branche billed_to_account_id ne puisse la sauver → 404 pour le tuteur
    // payeur (#5623). Même approche que get_quote (billing.rs).
    let quote_row = sqlx::query(
        "SELECT q.cabinet_id, q.patient_id, q.status, q.deposit_pct::double precision AS deposit_pct \
         FROM quote q \
         WHERE q.id = $1 AND q.deleted_at IS NULL",
    )
    .bind(body.quote_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = quote_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = quote_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = quote_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let deposit_pct: Option<f64> = quote_row
        .try_get("deposit_pct")
        .map_err(|_| AppError::Internal)?;

    if status != "signed" {
        return Err(AppError::InvalidStatus);
    }

    // Scope cabinet pour les opérations sur payment (tenant_isolation policy)
    // et sur quote_item (cf. commentaire ci-dessus) — doit précéder toute
    // lecture de quote_item.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Verrouille la ligne quote maintenant que le GUC cabinet est positionné :
    // deux POST /payments/intent concurrents sur le même devis se sérialisent
    // ici, si bien que le calcul du reste-dû ci-dessous voit toujours les
    // paiements déjà insérés par la transaction gagnante (garde TOCTOU, #3775 —
    // corrigée pour de bon cette fois, cf. commentaire plus haut).
    sqlx::query("SELECT id FROM quote WHERE id = $1 FOR UPDATE")
        .bind(body.quote_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Reste-à-charge réel du patient (total des lignes - part AMO - part AMC) —
    // même sous-requête que cabinet_quotes.rs (patient_share_cents exposé côté
    // cabinet). Le tiers-payant ne doit jamais forcer le patient à préfinancer
    // la part remboursée par l'assurance. Exécutée maintenant que le GUC
    // cabinet est posé, donc visible sous tenant_isolation.
    let patient_share_row = sqlx::query(
        "SELECT coalesce(sum((qi.qty * qi.unit_amount \
             - coalesce(qi.amo_part, 0) - coalesce(qi.amc_part, 0)) * 100), 0)::bigint \
             AS patient_share_cents \
         FROM quote_item qi WHERE qi.quote_id = $1",
    )
    .bind(body.quote_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let patient_share_cents: i64 = patient_share_row
        .try_get("patient_share_cents")
        .map_err(|_| AppError::Internal)?;

    // Montant restant dû = total du devis - paiements déjà en cours/aboutis (jamais
    // les `failed`/`refunded`, qui n'engagent aucune somme).
    let already_committed_row = sqlx::query(
        "SELECT COALESCE(SUM(amount * 100), 0)::bigint AS committed_cents \
         FROM payment \
         WHERE quote_id = $1 AND status IN ('pending', 'paid')",
    )
    .bind(body.quote_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let already_committed_cents: i64 = already_committed_row
        .try_get("committed_cents")
        .map_err(|_| AppError::Internal)?;
    let remaining_due_cents = patient_share_cents - already_committed_cents;

    // Acompte obligatoire (#3761) : deposit_pct était stocké à la création du
    // devis mais jamais imposé — un patient pouvait régler un acompte
    // arbitraire (ex. 1 centime) très en dessous du plancher demandé par le
    // cabinet. Le plancher s'applique tant qu'il n'est pas atteint, quel que
    // soit le `kind` déclaré ("deposit"/"installment"/"full") : sinon il
    // suffit de changer ce libellé pour le contourner entièrement (#4431).
    if let Some(pct) = deposit_pct {
        let min_deposit_cents = ((patient_share_cents as f64) * pct / 100.0).ceil() as i64;
        if already_committed_cents < min_deposit_cents
            && already_committed_cents + body.amount_cents < min_deposit_cents
        {
            return Err(AppError::ValidationError);
        }
    }

    if body.amount_cents > remaining_due_cents {
        return Err(AppError::ValidationError);
    }

    // Génère un client_secret stub (remplacé par l'appel Stripe réel post-T2).
    let client_secret = format!(
        "pi_{}_secret_{}",
        Uuid::new_v4().simple(),
        Uuid::new_v4().simple()
    );

    let insert_result = sqlx::query(
        "INSERT INTO payment \
         (cabinet_id, patient_id, quote_id, amount, currency, kind, provider, status, \
          idempotency_key, method, client_secret) \
         VALUES ($1, $2, $3, $4::numeric / 100, 'EUR', $5, 'stripe', 'pending', $6, $7, $8) \
         RETURNING id",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(body.quote_id)
    .bind(body.amount_cents)
    .bind(&body.kind)
    .bind(&idempotency_key)
    .bind(&body.method)
    .bind(&client_secret)
    .fetch_one(&mut *tx)
    .await;

    // Contrainte UNIQUE payment_idempotency_key_unique (permanente, sans fenêtre
    // de temps — contrairement au cache idempotency_keys, TTL 24h). Si la clé a
    // déjà servi pour un paiement mais que son entrée de cache a expiré (ou
    // n'existe plus), l'empreinte d'origine n'est plus disponible pour vérifier
    // qu'il s'agit bien du même patient/devis/montant : on refuse en 409 plutôt
    // que de laisser la violation UNIQUE remonter en 500, et plutôt que de
    // rejouer aveuglément une réponse qui pourrait appartenir à un autre
    // patient ayant choisi la même clé (#3867).
    let row = match insert_result {
        Ok(row) => row,
        Err(e) if is_unique_violation(&e) => {
            tracing::warn!(
                account_id = %claims.account_id,
                "idempotency key already bound to a payment outside the 24h cache window"
            );
            return Err(AppError::IdempotencyKeyConflict);
        }
        Err(_) => return Err(AppError::Internal),
    };

    let payment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    // Stocke la réponse + l'empreinte dans idempotency_keys pour les replays < 24h.
    sqlx::query(
        "INSERT INTO idempotency_keys (key, response, fingerprint) VALUES ($1, $2, $3) \
         ON CONFLICT (key) DO NOTHING",
    )
    .bind(&idempotency_key)
    .bind(serde_json::json!({"payment_id": payment_id, "client_secret": &client_secret}))
    .bind(&fingerprint)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        cabinet_id = %cabinet_id,
        payment_id = %payment_id,
        kind = %body.kind,
        method = %body.method,
        amount_cents = body.amount_cents,
        "payment intent created"
    );

    Ok((
        StatusCode::CREATED,
        Json(PaymentIntentResponse {
            payment_id,
            client_secret,
        }),
    ))
}

/// Corps de `POST /v1/payments/pharmacy-quote-intent`.
#[derive(Deserialize)]
pub struct PharmacyQuotePaymentIntentBody {
    pub pharmacy_quote_id: Uuid,
    pub method: String,
}

/// `POST /v1/payments/pharmacy-quote-intent` — crée un PaymentIntent Stripe
/// pour un devis d'officine accepté (#3505 : jusqu'ici un devis `accepted`
/// n'avait aucun chemin de paiement, contrairement au devis dentaire
/// `quote.status='signed'` → `POST /v1/payments/intent`).
///
/// Token `kind:"patient"` requis. Header `Idempotency-Key` obligatoire → `422`
/// si absent. Le devis (`pharmacy_quote_id`) doit être dans l'état `accepted`
/// → `409` sinon. Le montant est celui du devis (`total_cents`), jamais fourni
/// par le client. PCI délégué : seul le `client_secret` est transmis.
///
/// Un devis déjà couvert par un paiement `pending`/`paid` refuse tout nouvel
/// intent (`422`), même avec une clé d'idempotence différente (#3732).
pub async fn create_pharmacy_quote_payment_intent(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    headers: HeaderMap,
    Json(body): Json<PharmacyQuotePaymentIntentBody>,
) -> Result<(StatusCode, Json<PaymentIntentResponse>), AppError> {
    let idempotency_key = headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty())
        .ok_or(AppError::ValidationError)?
        .to_owned();

    if !["card", "apple_pay", "google_pay", "sepa"].contains(&body.method.as_str()) {
        return Err(AppError::ValidationError);
    }

    // Empreinte de la requête : une même clé rejouée avec un compte/devis/méthode
    // différent ne doit jamais renvoyer le paiement d'une autre requête (#3547, #3620).
    let fingerprint = format!(
        "account={}|pharmacy_quote={}|method={}",
        claims.account_id, body.pharmacy_quote_id, body.method
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    let cached = sqlx::query(
        "SELECT response, fingerprint FROM idempotency_keys \
         WHERE key = $1 AND created_at > now() - interval '24 hours'",
    )
    .bind(&idempotency_key)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(cached_row) = cached {
        let cached_fingerprint: Option<String> = cached_row
            .try_get("fingerprint")
            .map_err(|_| AppError::Internal)?;
        if cached_fingerprint.as_deref() != Some(fingerprint.as_str()) {
            tx.commit().await.map_err(|_| AppError::Internal)?;
            tracing::warn!(
                account_id = %claims.account_id,
                "pharmacy quote idempotency key replayed with a different fingerprint"
            );
            return Err(AppError::IdempotencyKeyConflict);
        }
        let resp: serde_json::Value = cached_row
            .try_get("response")
            .map_err(|_| AppError::Internal)?;
        let payment_id: Uuid = resp["payment_id"]
            .as_str()
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or(AppError::Internal)?;
        let client_secret: String = resp["client_secret"]
            .as_str()
            .map(|s| s.to_owned())
            .ok_or(AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok((
            StatusCode::CREATED,
            Json(PaymentIntentResponse {
                payment_id,
                client_secret,
            }),
        ));
    }

    // Scope patient pour lire le devis (policy pharmacy_quote_patient_select)
    // et la commande dont il découle (policy pharmacy_order_patient_select).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Pas de FOR UPDATE ici (contrairement à create_payment_intent / #3775) :
    // la policy RLS pharmacy_quote_patient_update n'autorise le verrou que sur
    // status='sent', donc un devis déjà 'accepted' deviendrait invisible sous
    // FOR UPDATE — la garde reste-dû ci-dessous suffit à empêcher la race.
    let quote_row = sqlx::query(
        "SELECT pq.status, pq.total_cents, po.cabinet_id, po.status AS order_status \
         FROM pharmacy_quote pq \
         JOIN pharmacy_order po ON po.id = pq.order_id \
         WHERE pq.id = $1 AND pq.patient_account_id = $2",
    )
    .bind(body.pharmacy_quote_id)
    .bind(claims.account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let status: String = quote_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let total_cents: i64 = quote_row
        .try_get("total_cents")
        .map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = quote_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let order_status: String = quote_row
        .try_get("order_status")
        .map_err(|_| AppError::Internal)?;

    // #4415/#5476 : la commande ancre doit rester active au moment du
    // paiement — sinon une commande rejetée/annulée après acceptation du
    // devis reste payable (charge fantôme sur des médicaments jamais
    // délivrés).
    if status != "accepted" || !matches!(order_status.as_str(), "received" | "preparing" | "ready")
    {
        return Err(AppError::InvalidStatus);
    }

    // Scope cabinet (tenant_isolation) pour résoudre le patient cabinet-scopé
    // et insérer le paiement — même cabinet que celui d'origine de la
    // prescription/commande (`pharmacy_order.cabinet_id`).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Reste dû : contrairement au devis dentaire (montant partiel possible),
    // ce devis se règle toujours en une fois (`total_cents`) — la garde se
    // réduit donc à « aucun paiement pending/paid déjà engagé sur ce devis »
    // (#3732 : sans cette garde, chaque appel avec une clé d'idempotence
    // fraîche insérait un nouveau paiement plein-montant, sans borne).
    let already_committed_row = sqlx::query(
        "SELECT COALESCE(SUM(amount * 100), 0)::bigint AS committed_cents \
         FROM payment \
         WHERE pharmacy_quote_id = $1 AND status IN ('pending', 'paid')",
    )
    .bind(body.pharmacy_quote_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let already_committed_cents: i64 = already_committed_row
        .try_get("committed_cents")
        .map_err(|_| AppError::Internal)?;
    if already_committed_cents >= total_cents {
        return Err(AppError::ValidationError);
    }

    let patient_id: Uuid =
        sqlx::query("SELECT id FROM patient WHERE cabinet_id = $1 AND patient_account_id = $2")
            .bind(cabinet_id)
            .bind(claims.account_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::Internal)?
            .try_get("id")
            .map_err(|_| AppError::Internal)?;

    let client_secret = format!(
        "pi_{}_secret_{}",
        Uuid::new_v4().simple(),
        Uuid::new_v4().simple()
    );

    let insert_result = sqlx::query(
        "INSERT INTO payment \
         (cabinet_id, patient_id, pharmacy_quote_id, amount, currency, kind, provider, status, \
          idempotency_key, method, client_secret) \
         VALUES ($1, $2, $3, $4::numeric / 100, 'EUR', 'full', 'stripe', 'pending', $5, $6, $7) \
         RETURNING id",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(body.pharmacy_quote_id)
    .bind(total_cents)
    .bind(&idempotency_key)
    .bind(&body.method)
    .bind(&client_secret)
    .fetch_one(&mut *tx)
    .await;

    // Même garde-fou que create_payment_intent : contrainte UNIQUE permanente
    // vs cache idempotency_keys à TTL 24h (#3867). #4418 : deux contraintes
    // UNIQUE distinctes peuvent déclencher 23505 ici — celle sur
    // idempotency_key (rejeu hors fenêtre de cache) et la nouvelle
    // payment_pharmacy_quote_pending_unique (#4418, deux intents concurrents
    // sur le même devis) — distinguées par nom pour ne pas mapper la 2nde en
    // IdempotencyKeyConflict (message trompeur : ce n'est pas un rejeu, mais
    // une race entre deux clés différentes sur le même devis).
    let row = match insert_result {
        Ok(row) => row,
        Err(e)
            if unique_violation_constraint(&e).as_deref()
                == Some("payment_pharmacy_quote_pending_unique") =>
        {
            tracing::warn!(
                account_id = %claims.account_id,
                pharmacy_quote_id = %body.pharmacy_quote_id,
                "concurrent pharmacy quote payment intent rejected by DB-level race guard"
            );
            return Err(AppError::ValidationError);
        }
        Err(e) if is_unique_violation(&e) => {
            tracing::warn!(
                account_id = %claims.account_id,
                "idempotency key already bound to a pharmacy quote payment outside the 24h cache window"
            );
            return Err(AppError::IdempotencyKeyConflict);
        }
        Err(_) => return Err(AppError::Internal),
    };

    let payment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO idempotency_keys (key, response, fingerprint) VALUES ($1, $2, $3) \
         ON CONFLICT (key) DO NOTHING",
    )
    .bind(&idempotency_key)
    .bind(serde_json::json!({"payment_id": payment_id, "client_secret": &client_secret}))
    .bind(&fingerprint)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        cabinet_id = %cabinet_id,
        payment_id = %payment_id,
        pharmacy_quote_id = %body.pharmacy_quote_id,
        "pharmacy quote payment intent created"
    );

    Ok((
        StatusCode::CREATED,
        Json(PaymentIntentResponse {
            payment_id,
            client_secret,
        }),
    ))
}
