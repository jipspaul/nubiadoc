//! Handlers facturation : GET /v1/quotes, GET /v1/quotes/:id, POST /v1/payments/intent,
//! POST /v1/cabinet/quotes (création devis côté cabinet).
//!
//! Alias patient `/v1/billing/quotes/*` (BR5) : les handlers `billing_*` délèguent
//! aux handlers pro-existants via redirection logique (même code, alias contractuel).

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProPractitionerClaims},
    reviews::is_unique_violation,
    AppState,
};

#[derive(Deserialize)]
pub struct ListQuotesQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct QuoteItem {
    pub id: Uuid,
    pub status: String,
    pub total_amount_cents: i64,
    pub currency: String,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct ListQuotesResponse {
    pub data: Vec<QuoteItem>,
    pub page: PageInfo,
}

fn encode_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/quotes` — devis du patient connecté, tous cabinets confondus.
///
/// Token `kind:"patient"` requis ; token pro → `403`.
/// RLS via `app.patient_account_id` (policy `quote_patient_read`, migration 0029).
/// Filtre optionnel `?status=` (draft|sent|signed|refused|expired).
/// Pagination cursor-based (`limit` + `cursor`), tri `created_at DESC`.
/// Montants exposés en centimes entiers (`amount_cents`).
pub async fn list_quotes(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<ListQuotesQuery>,
) -> Result<Json<ListQuotesResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let fetch_limit = limit + 1;

    let cursor = params.cursor.as_deref().and_then(decode_cursor);

    let status_clause = if params.status.is_some() {
        " AND q.status = $2"
    } else {
        ""
    };

    // Cursor binds shift by 1 when status is present.
    let cursor_clause = match (params.status.is_some(), cursor.is_some()) {
        (false, true) => " AND (q.created_at < $2 OR (q.created_at = $2 AND q.id < $3))",
        (true, true) => " AND (q.created_at < $3 OR (q.created_at = $3 AND q.id < $4))",
        _ => "",
    };

    let sql = format!(
        "SELECT q.id, q.status, (q.total_amount * 100)::bigint AS amount_cents, \
                q.currency, q.created_at \
         FROM quote q \
         WHERE q.deleted_at IS NULL\
         {status_clause}{cursor_clause} \
         ORDER BY q.created_at DESC, q.id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — quote_patient_read (migration 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = match (params.status.as_deref(), cursor) {
        (None, None) => sqlx::query(&sql)
            .bind(fetch_limit)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        (Some(st), None) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(st)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        (None, Some((cursor_at, cursor_id))) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_at)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        (Some(st), Some((cursor_at, cursor_id))) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(st)
            .bind(cursor_at)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<QuoteItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let amount_cents: i64 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        let currency: String = row.try_get("currency").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(QuoteItem {
            id,
            status,
            total_amount_cents: amount_cents,
            currency: currency.trim().to_string(),
            created_at: created_at.to_rfc3339(),
        });
    }

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        account_id = %claims.account_id,
        count = data.len(),
        has_more,
        "quotes listed"
    );

    Ok(Json(ListQuotesResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

/// Ligne d'un devis (réponse détail).
#[derive(Serialize)]
pub struct QuoteLineItem {
    pub id: Uuid,
    pub label: String,
    pub ccam_code: Option<String>,
    pub tooth: Option<String>,
    pub qty_cents: i64,
    pub unit_amount_cents: i64,
    pub amc_part_cents: Option<i64>,
    pub amo_part_cents: Option<i64>,
}

/// Réponse de `GET /v1/quotes/:id`.
#[derive(Serialize)]
pub struct QuoteDetail {
    pub id: Uuid,
    pub status: String,
    pub version: i32,
    pub total_amount_cents: i64,
    pub currency: String,
    pub signed_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
    pub items: Vec<QuoteLineItem>,
}

/// `GET /v1/quotes/:id` — détail d'un devis du patient connecté.
///
/// Token `kind:"patient"` requis ; token pro → `403`.
/// RLS via `app.patient_account_id` (policy `quote_patient_read`, migration 0029).
/// Retourne `404` si le devis n'existe pas ou n'appartient pas au patient.
pub async fn get_quote(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteDetail>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — quote_patient_read (migration 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let quote_row = sqlx::query(
        "SELECT q.id, q.cabinet_id, q.status, q.version, \
                (q.total_amount * 100)::bigint AS amount_cents, \
                q.currency, q.signed_at, q.created_at, q.updated_at \
         FROM quote q \
         WHERE q.id = $1 AND q.deleted_at IS NULL",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = quote_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;

    // Scope cabinet pour lire les lignes du devis (tenant_isolation sur quote_item).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let item_rows = sqlx::query(
        "SELECT qi.id, qi.label, qi.ccam_code, qi.tooth, \
                (qi.qty * 100)::bigint AS qty_cents, \
                (qi.unit_amount * 100)::bigint AS unit_amount_cents, \
                (qi.amc_part * 100)::bigint AS amc_part_cents, \
                (qi.amo_part * 100)::bigint AS amo_part_cents \
         FROM quote_item qi \
         WHERE qi.quote_id = $1 \
         ORDER BY qi.id",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let status: String = quote_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let version: i32 = quote_row
        .try_get("version")
        .map_err(|_| AppError::Internal)?;
    let amount_cents: i64 = quote_row
        .try_get("amount_cents")
        .map_err(|_| AppError::Internal)?;
    let currency: String = quote_row
        .try_get("currency")
        .map_err(|_| AppError::Internal)?;
    let signed_at: Option<chrono::DateTime<chrono::Utc>> = quote_row
        .try_get("signed_at")
        .map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> = quote_row
        .try_get("created_at")
        .map_err(|_| AppError::Internal)?;
    let updated_at: chrono::DateTime<chrono::Utc> = quote_row
        .try_get("updated_at")
        .map_err(|_| AppError::Internal)?;

    let mut items = Vec::with_capacity(item_rows.len());
    for row in &item_rows {
        let item_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let ccam_code: Option<String> = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
        let qty_cents: i64 = row.try_get("qty_cents").map_err(|_| AppError::Internal)?;
        let unit_amount_cents: i64 = row
            .try_get("unit_amount_cents")
            .map_err(|_| AppError::Internal)?;
        let amc_part_cents: Option<i64> = row
            .try_get("amc_part_cents")
            .map_err(|_| AppError::Internal)?;
        let amo_part_cents: Option<i64> = row
            .try_get("amo_part_cents")
            .map_err(|_| AppError::Internal)?;
        items.push(QuoteLineItem {
            id: item_id,
            label,
            ccam_code,
            tooth,
            qty_cents,
            unit_amount_cents,
            amc_part_cents,
            amo_part_cents,
        });
    }

    tracing::info!(
        account_id = %claims.account_id,
        quote_id = %id,
        "quote detail fetched"
    );

    Ok(Json(QuoteDetail {
        id,
        status,
        version,
        total_amount_cents: amount_cents,
        currency: currency.trim().to_string(),
        signed_at: signed_at.map(|dt| dt.to_rfc3339()),
        created_at: created_at.to_rfc3339(),
        updated_at: updated_at.to_rfc3339(),
        items,
    }))
}

/// Réponse de `POST /v1/quotes/:id/sign`.
#[derive(Serialize)]
pub struct SignQuoteResponse {
    pub signed: bool,
    pub signed_at: String,
}

/// `POST /v1/quotes/:id/sign` — signature stub d'un devis par le patient connecté.
///
/// Token `kind:"patient"` requis ; token pro → `403`.
/// RLS via `app.patient_account_id` (policy `quote_patient_read`, migration 0029/0134 —
/// `draft` est invisible côté patient).
/// Retourne `404` si le devis n'appartient pas au patient authentifié.
/// Retourne `409` si le devis n'est pas au statut `sent` (`draft`/`refused`/`expired` :
/// seul un devis envoyé par le cabinet peut être signé).
/// Met à jour le devis : `status = 'signed'`, `signed_at = now()`.
/// Retourne `200 { signed: true, signed_at: "...ISO8601..." }` (stub Yousign — pas d'appel réel).
pub async fn sign_quote(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<SignQuoteResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — quote_patient_read (migration 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le devis appartient au patient (JOIN patient → patient_account_id).
    // RLS fail-closed : si le devis n'existe pas ou hors tenant → 404.
    let row = sqlx::query(
        "SELECT q.cabinet_id, q.status, q.signed_at \
         FROM quote q \
         JOIN patient p ON p.id = q.patient_id \
         WHERE q.id = $1 AND q.deleted_at IS NULL \
           AND p.patient_account_id = $2",
    )
    .bind(id)
    .bind(claims.account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let current_status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    // Idempotence : un devis déjà signé est immuable (trigger `quote_signed_immutable`).
    // On renvoie 200 avec la date de signature existante plutôt que de heurter le
    // trigger (qui provoquerait une 500).
    if current_status == "signed" {
        let existing_signed_at: Option<chrono::DateTime<chrono::Utc>> =
            row.try_get("signed_at").map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(SignQuoteResponse {
            signed: true,
            signed_at: existing_signed_at
                .map(|d| d.to_rfc3339())
                .unwrap_or_default(),
        }));
    }

    // `sent` est l'étape obligatoire entre `draft` et `signed` (cf. send_cabinet_quote,
    // ligne ~1094) : un devis pas encore envoyé par le cabinet ne peut pas être signé.
    if current_status != "sent" {
        return Err(AppError::InvalidStatus);
    }

    // Scope cabinet pour l'UPDATE (tenant_isolation policy sur quote).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Transition stub Yousign : sent → signed.
    let update_row = sqlx::query(
        "UPDATE quote \
         SET status = 'signed', signed_at = now(), updated_at = now() \
         WHERE id = $1 AND cabinet_id = $2 AND status = 'sent' \
         RETURNING signed_at",
    )
    .bind(id)
    .bind(cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let signed_at: chrono::DateTime<chrono::Utc> = update_row
        .try_get("signed_at")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        quote_id = %id,
        "quote signed"
    );

    Ok(Json(SignQuoteResponse {
        signed: true,
        signed_at: signed_at.to_rfc3339(),
    }))
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

    let quote_row = sqlx::query(
        "SELECT q.cabinet_id, q.patient_id, q.status, (q.total_amount * 100)::bigint AS total_amount_cents \
         FROM quote q \
         JOIN patient p ON p.id = q.patient_id \
         WHERE q.id = $1 AND q.deleted_at IS NULL \
           AND p.patient_account_id = $2",
    )
    .bind(body.quote_id)
    .bind(claims.account_id)
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
    let total_amount_cents: i64 = quote_row
        .try_get("total_amount_cents")
        .map_err(|_| AppError::Internal)?;

    if status != "signed" {
        return Err(AppError::InvalidStatus);
    }

    // Scope cabinet pour les opérations sur payment (tenant_isolation policy).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
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
    let remaining_due_cents = total_amount_cents - already_committed_cents;

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

    let quote_row = sqlx::query(
        "SELECT pq.status, pq.total_cents, po.cabinet_id \
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

    if status != "accepted" {
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
    // vs cache idempotency_keys à TTL 24h (#3867).
    let row = match insert_result {
        Ok(row) => row,
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

// ── POST /v1/cabinet/quotes ──────────────────────────────────────────────────

/// Un item du devis dans le body de création.
#[derive(Deserialize)]
pub struct QuoteItemInput {
    pub label: String,
    pub amount_cents: i64,
}

/// Body de `POST /v1/cabinet/quotes`.
#[derive(Deserialize)]
pub struct CreateCabinetQuoteBody {
    pub patient_id: Uuid,
    pub items: Vec<QuoteItemInput>,
    pub deposit_pct: Option<f64>,
}

/// Réponse de `POST /v1/cabinet/quotes`.
#[derive(Serialize)]
pub struct CreateCabinetQuoteResponse {
    pub quote_id: Uuid,
    pub total_amount_cents: i64,
}

/// `POST /v1/cabinet/quotes` — crée un devis (statut `draft`) avec ses lignes.
///
/// - Auth JWT pro `practitioner` ou `admin` requis — `secretary` → 403, patient → 403.
/// - `cabinet_id` extrait du JWT.
/// - `items` vide → 422.
/// - `amount_cents` de chaque ligne doit être `> 0` → 422 sinon.
/// - `deposit_pct` doit être entre 0 et 100 si fourni → 422 sinon.
/// - `total_amount` calculé depuis les items (`sum(amount_cents) / 100`).
/// - Insert `quote` + N `quote_item` dans une transaction RLS-scopée.
/// - Retourne `201 { quote_id, total_amount_cents }`.
pub async fn create_cabinet_quote(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<CreateCabinetQuoteBody>,
) -> Result<(StatusCode, Json<CreateCabinetQuoteResponse>), AppError> {
    if body.items.is_empty() {
        return Err(AppError::ValidationError);
    }
    if body.items.iter().any(|i| i.amount_cents <= 0) {
        return Err(AppError::ValidationError);
    }
    if let Some(pct) = body.deposit_pct {
        if !(0.0..=100.0).contains(&pct) {
            return Err(AppError::ValidationError);
        }
    }

    let total_cents: i64 = body.items.iter().map(|i| i.amount_cents).sum();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope RLS tenant.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le tenant).
    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(body.patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // Insère le devis.
    let quote_row = sqlx::query(
        "INSERT INTO quote \
         (cabinet_id, patient_id, status, total_amount, currency, deposit_pct) \
         VALUES ($1, $2, 'draft', $3::numeric / 100, 'EUR', $4) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.patient_id)
    .bind(total_cents)
    .bind(body.deposit_pct)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let quote_id: Uuid = quote_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Insère les lignes.
    for item in &body.items {
        sqlx::query(
            "INSERT INTO quote_item \
             (cabinet_id, quote_id, label, unit_amount) \
             VALUES ($1, $2, $3, $4::numeric / 100)",
        )
        .bind(claims.cabinet_id)
        .bind(quote_id)
        .bind(&item.label)
        .bind(item.amount_cents)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        cabinet_id = %claims.cabinet_id,
        quote_id = %quote_id,
        total_cents,
        "cabinet quote created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateCabinetQuoteResponse {
            quote_id,
            total_amount_cents: total_cents,
        }),
    ))
}

// ---------------------------------------------------------------------------
// POST /v1/billing/quotes/:id/deposit (BR5)
// Alias patient : crée un PaymentIntent de type `deposit` pour le devis.
// Délègue à `create_payment_intent` avec kind="deposit" injecté dans le body.
// ---------------------------------------------------------------------------

/// Corps de `POST /v1/billing/quotes/:id/deposit`.
#[derive(Deserialize)]
pub struct DepositBody {
    pub amount_cents: i64,
    pub method: String,
}

/// `POST /v1/billing/quotes/:id/deposit` — acompte patient (BR5).
///
/// Token `kind:"patient"` requis.
/// Header `Idempotency-Key` obligatoire → `422` si absent.
/// Le devis doit être dans l'état `signed` → `409` sinon.
/// Délègue au handler `create_payment_intent` avec `kind = "deposit"`.
pub async fn billing_deposit(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    headers: HeaderMap,
    Path(id): Path<Uuid>,
    Json(body): Json<DepositBody>,
) -> Result<(StatusCode, Json<PaymentIntentResponse>), AppError> {
    let intent_body = PaymentIntentBody {
        quote_id: id,
        kind: "deposit".to_string(),
        amount_cents: body.amount_cents,
        method: body.method,
    };
    create_payment_intent(State(state), claims, headers, Json(intent_body)).await
}

// ---------------------------------------------------------------------------
// POST /v1/billing/quotes/:id/confirm_signature (BR5)
// Alias patient : confirme la signature d'un devis (idempotent avec sign_quote).
// ---------------------------------------------------------------------------

/// `POST /v1/billing/quotes/:id/confirm_signature` — confirmation signature patient (BR5).
///
/// Token `kind:"patient"` requis.
/// Délègue à `sign_quote` : met `status = 'signed'`, `signed_at = now()`.
/// Idempotent : un devis déjà signé renvoie `200` sans erreur.
pub async fn billing_confirm_signature(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<SignQuoteResponse>, AppError> {
    sign_quote(State(state), claims, Path(id)).await
}

// ---------------------------------------------------------------------------
// GET /v1/cabinet/quotes — suivi devis côté cabinet (doc12 §10)
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct ListCabinetQuotesQuery {
    pub status: Option<String>,
    /// `limit` (défaut 200, max 500) et `offset` bornent le résultat (#3521 :
    /// avant, l'endpoint renvoyait tous les devis du cabinet en tableau nu).
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    /// Capté uniquement pour rejeter explicitement `?page` (non supporté ici :
    /// pagination via `limit`/`offset`). Avant #3521 : ignoré silencieusement.
    pub page: Option<String>,
}

/// Un devis vu du cabinet. `total_amount` en **centimes** (conventions doc12 §1.7).
#[derive(Serialize)]
pub struct CabinetQuoteItem {
    pub id: Uuid,
    pub patient_id: Option<Uuid>,
    pub patient_name: Option<String>,
    pub status: String,
    pub total_amount: i64,
    pub patient_share_cents: i64,
    pub created_at: String,
}

/// `GET /v1/cabinet/quotes` — liste les devis du cabinet courant.
///
/// Token pro requis (secretary, practitioner, admin, manager). `cabinet_id`
/// extrait du JWT, RLS scopée via `app.current_cabinet_id` (fail-closed).
/// Filtre optionnel `?status=`. Tri `created_at DESC`.
pub async fn list_cabinet_quotes(
    State(state): State<AppState>,
    claims: crate::auth::ProSecretaryPlusClaims,
    Query(params): Query<ListCabinetQuotesQuery>,
) -> Result<Json<Vec<CabinetQuoteItem>>, AppError> {
    if params.page.is_some() {
        return Err(AppError::UnsupportedPageParam);
    }
    let limit: i64 = params.limit.unwrap_or(200).clamp(1, 500);
    let offset: i64 = params.offset.unwrap_or(0).max(0);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let base_sql = "SELECT q.id, q.patient_id, \
                    trim(concat(p.first_name, ' ', p.last_name)) AS patient_name, \
                    q.status, (q.total_amount * 100)::bigint AS amount_cents, \
                    (SELECT coalesce(sum((qi.qty * qi.unit_amount \
                        - coalesce(qi.amo_part, 0) - coalesce(qi.amc_part, 0)) * 100), 0)::bigint \
                     FROM quote_item qi WHERE qi.quote_id = q.id) AS patient_share_cents, \
                    q.created_at \
             FROM quote q \
             LEFT JOIN patient p ON p.id = q.patient_id \
             WHERE q.cabinet_id = $1";

    let rows = if let Some(ref status) = params.status {
        sqlx::query(&format!(
            "{base_sql} AND q.status = $2 ORDER BY q.created_at DESC LIMIT $3 OFFSET $4"
        ))
        .bind(claims.cabinet_id)
        .bind(status)
        .bind(limit)
        .bind(offset)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    } else {
        sqlx::query(&format!(
            "{base_sql} ORDER BY q.created_at DESC LIMIT $2 OFFSET $3"
        ))
        .bind(claims.cabinet_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let items = rows
        .into_iter()
        .map(|row| {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let patient_id: Option<Uuid> =
                row.try_get("patient_id").map_err(|_| AppError::Internal)?;
            let patient_name: Option<String> = row
                .try_get("patient_name")
                .map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let amount_cents: i64 = row
                .try_get("amount_cents")
                .map_err(|_| AppError::Internal)?;
            let patient_share_cents: i64 = row
                .try_get("patient_share_cents")
                .map_err(|_| AppError::Internal)?;
            let created_at: chrono::DateTime<chrono::Utc> =
                row.try_get("created_at").map_err(|_| AppError::Internal)?;
            Ok(CabinetQuoteItem {
                id,
                patient_id,
                patient_name: patient_name.filter(|n| !n.is_empty()),
                status,
                total_amount: amount_cents,
                patient_share_cents,
                created_at: created_at.to_rfc3339(),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        count = items.len(),
        "cabinet quotes listed"
    );

    Ok(Json(items))
}

// ---------------------------------------------------------------------------
// GET /v1/cabinet/quotes/:id — détail d'un devis côté cabinet (secrétariat+)
// ---------------------------------------------------------------------------

/// Une ligne de devis vue du cabinet. Montants en **centimes**.
///
/// Cloisonnement (R.4127-72) : on n'expose que le libellé administratif de
/// l'acte et les montants (aucun code CCAM ni numéro de dent, qui relèvent du
/// clinique et ne sont pas nécessaires au suivi financier du secrétariat).
#[derive(Serialize)]
pub struct CabinetQuoteLineItem {
    pub id: Uuid,
    pub label: String,
    pub total_amount: i64,
    pub patient_share_cents: i64,
}

/// Réponse de `GET /v1/cabinet/quotes/:id`. Montants en **centimes**.
#[derive(Serialize)]
pub struct CabinetQuoteDetail {
    pub id: Uuid,
    pub patient_id: Option<Uuid>,
    pub patient_name: Option<String>,
    pub status: String,
    pub total_amount: i64,
    pub patient_share_cents: i64,
    pub created_at: String,
    pub signed_at: Option<String>,
    pub items: Vec<CabinetQuoteLineItem>,
}

/// `GET /v1/cabinet/quotes/:id` — détail d'un devis du cabinet courant.
///
/// Token pro requis (secretary, practitioner, admin, manager). `cabinet_id`
/// extrait du JWT, RLS scopée via `app.current_cabinet_id` (fail-closed).
/// `404` si le devis n'existe pas ou n'appartient pas au cabinet.
///
/// Pendant clairement identifié de `GET /v1/cabinet/quotes` : le détail patient
/// (`GET /v1/quotes/:id`) est réservé au token patient (403 pour un pro), d'où
/// la nécessité d'une route cabinet dédiée pour le secrétariat.
pub async fn get_cabinet_quote(
    State(state): State<AppState>,
    claims: crate::auth::ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<CabinetQuoteDetail>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let quote_row = sqlx::query(
        "SELECT q.id, q.patient_id, \
                trim(concat(p.first_name, ' ', p.last_name)) AS patient_name, \
                q.status, (q.total_amount * 100)::bigint AS amount_cents, \
                q.signed_at, q.created_at \
         FROM quote q \
         LEFT JOIN patient p ON p.id = q.patient_id \
         WHERE q.id = $1 AND q.cabinet_id = $2 AND q.deleted_at IS NULL",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let item_rows = sqlx::query(
        "SELECT qi.id, qi.label, \
                (qi.qty * qi.unit_amount * 100)::bigint AS total_cents, \
                ((qi.qty * qi.unit_amount \
                  - coalesce(qi.amo_part, 0) - coalesce(qi.amc_part, 0)) * 100)::bigint \
                  AS patient_share_cents \
         FROM quote_item qi \
         WHERE qi.quote_id = $1 \
         ORDER BY qi.id",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let patient_id: Option<Uuid> = quote_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let patient_name: Option<String> = quote_row
        .try_get("patient_name")
        .map_err(|_| AppError::Internal)?;
    let status: String = quote_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let amount_cents: i64 = quote_row
        .try_get("amount_cents")
        .map_err(|_| AppError::Internal)?;
    let signed_at: Option<chrono::DateTime<chrono::Utc>> = quote_row
        .try_get("signed_at")
        .map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> = quote_row
        .try_get("created_at")
        .map_err(|_| AppError::Internal)?;

    let mut items = Vec::with_capacity(item_rows.len());
    let mut patient_share_total: i64 = 0;
    for row in &item_rows {
        let item_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let total_amount: i64 = row.try_get("total_cents").map_err(|_| AppError::Internal)?;
        let patient_share_cents: i64 = row
            .try_get("patient_share_cents")
            .map_err(|_| AppError::Internal)?;
        patient_share_total += patient_share_cents;
        items.push(CabinetQuoteLineItem {
            id: item_id,
            label,
            total_amount,
            patient_share_cents,
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        quote_id = %id,
        "cabinet quote detail fetched"
    );

    Ok(Json(CabinetQuoteDetail {
        id,
        patient_id,
        patient_name: patient_name.filter(|n| !n.is_empty()),
        status,
        total_amount: amount_cents,
        patient_share_cents: patient_share_total,
        created_at: created_at.to_rfc3339(),
        signed_at: signed_at.map(|d| d.to_rfc3339()),
        items,
    }))
}

// ── POST /v1/cabinet/quotes/:id/send ─────────────────────────────────────────

/// Réponse de `POST /v1/cabinet/quotes/:id/send`.
#[derive(Serialize)]
pub struct SendCabinetQuoteResponse {
    pub id: Uuid,
    pub status: String,
    pub sent: bool,
}

/// `POST /v1/cabinet/quotes/:id/send` — envoie un devis (brouillon) au patient.
///
/// Token pro requis (secretary, practitioner, admin, manager) — patient → 403.
/// `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// - Devis inexistant ou hors tenant → 404 (`not_found`).
/// - Transition `draft → sent` : rend le devis visible côté patient (WEDGE).
/// - Idempotence : un devis déjà `sent` renvoie `200` sans nouvelle écriture.
/// - Devis `signed`/`refused`/`expired` → 409 (`invalid_status`).
pub async fn send_cabinet_quote(
    State(state): State<AppState>,
    claims: crate::auth::ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<SendCabinetQuoteResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope RLS tenant (fail-closed : hors cabinet → devis invisible → 404).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT status FROM quote \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    // Idempotence : déjà envoyé → 200 sans nouvelle écriture.
    if status == "sent" {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(SendCabinetQuoteResponse {
            id,
            status,
            sent: true,
        }));
    }

    // Seul un brouillon peut être envoyé (signed/refused/expired → 409).
    if status != "draft" {
        return Err(AppError::InvalidStatus);
    }

    let updated = sqlx::query(
        "UPDATE quote SET status = 'sent', updated_at = now() \
         WHERE id = $1 AND cabinet_id = $2 \
         RETURNING status",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let status: String = updated.try_get("status").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        cabinet_id = %claims.cabinet_id,
        quote_id = %id,
        "cabinet quote sent to patient"
    );

    Ok(Json(SendCabinetQuoteResponse {
        id,
        status,
        sent: true,
    }))
}

// ── GET /v1/payments ─────────────────────────────────────────────────────────

/// Un paiement du patient connecté.
#[derive(Serialize)]
pub struct PaymentItem {
    pub payment_id: Uuid,
    pub quote_id: Option<Uuid>,
    pub pharmacy_quote_id: Option<Uuid>,
    pub kind: String,
    pub status: String,
    pub amount_cents: i64,
    pub currency: String,
    pub created_at: String,
}

/// Réponse de `GET /v1/payments`.
#[derive(Serialize)]
pub struct ListPaymentsResponse {
    pub data: Vec<PaymentItem>,
}

/// `GET /v1/payments` — paiements du patient connecté, tous cabinets confondus (#3238).
///
/// Token `kind:"patient"` requis. RLS `payment_patient_read` via
/// `app.patient_account_id` (migration 0029) — aucune fuite cross-patient.
/// Tri `created_at` DESC, 100 max.
pub async fn list_payments(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<ListPaymentsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, quote_id, pharmacy_quote_id, kind, status, \
                (amount * 100)::bigint AS amount_cents, \
                currency, created_at \
         FROM payment \
         ORDER BY created_at DESC \
         LIMIT 100",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|r| {
            let created_at: chrono::DateTime<chrono::Utc> =
                r.try_get("created_at").map_err(|_| AppError::Internal)?;
            let currency: String = r.try_get("currency").map_err(|_| AppError::Internal)?;
            Ok(PaymentItem {
                payment_id: r.try_get("id").map_err(|_| AppError::Internal)?,
                quote_id: r.try_get("quote_id").map_err(|_| AppError::Internal)?,
                pharmacy_quote_id: r
                    .try_get("pharmacy_quote_id")
                    .map_err(|_| AppError::Internal)?,
                kind: r.try_get("kind").map_err(|_| AppError::Internal)?,
                status: r.try_get("status").map_err(|_| AppError::Internal)?,
                amount_cents: r.try_get("amount_cents").map_err(|_| AppError::Internal)?,
                currency: currency.trim().to_string(),
                created_at: created_at.to_rfc3339(),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(ListPaymentsResponse { data }))
}
