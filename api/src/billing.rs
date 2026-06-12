//! Handlers facturation : GET /v1/quotes, GET /v1/quotes/:id, POST /v1/payments/intent,
//! POST /v1/cabinet/quotes (création devis côté cabinet).

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProPractitionerClaims},
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
/// RLS via `app.patient_account_id` (policy `quote_patient_read`, migration 0029).
/// Retourne `404` si le devis n'appartient pas au patient authentifié.
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
        "SELECT q.cabinet_id \
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

    // Scope cabinet pour l'UPDATE (tenant_isolation policy sur quote).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Transition stub Yousign : draft → signed.
    let update_row = sqlx::query(
        "UPDATE quote \
         SET status = 'signed', signed_at = now(), updated_at = now() \
         WHERE id = $1 AND cabinet_id = $2 \
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

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient pour lire le devis via la policy quote_patient_read (migration 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let quote_row = sqlx::query(
        "SELECT q.cabinet_id, q.patient_id, q.status \
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

    if status != "signed" {
        return Err(AppError::InvalidStatus);
    }

    // Scope cabinet pour les opérations sur payment (tenant_isolation policy).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Idempotence : retourne le paiement existant si la clé est déjà connue.
    let existing = sqlx::query(
        "SELECT id, client_secret FROM payment \
         WHERE cabinet_id = $1 AND idempotency_key = $2",
    )
    .bind(cabinet_id)
    .bind(&idempotency_key)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(row) = existing {
        let payment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let client_secret: String = row
            .try_get("client_secret")
            .map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        tracing::info!(
            account_id = %claims.account_id,
            payment_id = %payment_id,
            "payment intent idempotent hit"
        );
        return Ok((
            StatusCode::CREATED,
            Json(PaymentIntentResponse {
                payment_id,
                client_secret,
            }),
        ));
    }

    // Génère un client_secret stub (remplacé par l'appel Stripe réel post-T2).
    let client_secret = format!(
        "pi_{}_secret_{}",
        Uuid::new_v4().simple(),
        Uuid::new_v4().simple()
    );

    let row = sqlx::query(
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
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let payment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

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
// GET /v1/cabinet/quotes — suivi devis côté cabinet (doc12 §10)
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct ListCabinetQuotesQuery {
    pub status: Option<String>,
}

/// Un devis vu du cabinet. `total_amount` en **centimes** (conventions doc12 §1.7).
#[derive(Serialize)]
pub struct CabinetQuoteItem {
    pub id: Uuid,
    pub patient_id: Option<Uuid>,
    pub patient_name: Option<String>,
    pub status: String,
    pub total_amount: i64,
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
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let base_sql = "SELECT q.id, q.patient_id, \
                    trim(concat(p.first_name, ' ', p.last_name)) AS patient_name, \
                    q.status, (q.total_amount * 100)::bigint AS amount_cents, q.created_at \
             FROM quote q \
             LEFT JOIN patient p ON p.id = q.patient_id \
             WHERE q.cabinet_id = $1";

    let rows = if let Some(ref status) = params.status {
        sqlx::query(&format!(
            "{base_sql} AND q.status = $2 ORDER BY q.created_at DESC"
        ))
        .bind(claims.cabinet_id)
        .bind(status)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    } else {
        sqlx::query(&format!("{base_sql} ORDER BY q.created_at DESC"))
            .bind(claims.cabinet_id)
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
            let created_at: chrono::DateTime<chrono::Utc> =
                row.try_get("created_at").map_err(|_| AppError::Internal)?;
            Ok(CabinetQuoteItem {
                id,
                patient_id,
                patient_name: patient_name.filter(|n| !n.is_empty()),
                status,
                total_amount: amount_cents,
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
