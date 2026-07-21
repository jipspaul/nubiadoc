//! Handlers `/v1/cabinet/quotes` — suivi et création des devis côté cabinet
//! (praticien/secrétariat), doc12 §10.
//!
//! Extrait de `billing.rs` (refactor de taille, #4056 / CLAUDE.md plafond
//! 700 lignes) — module autonome, mêmes handlers/contrats, aucun changement
//! fonctionnel.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

// ── POST /v1/cabinet/quotes ──────────────────────────────────────────────────

/// Un item du devis dans le body de création.
///
/// `ccam_code`/`tooth`/`amo_part_cents`/`amc_part_cents` alignent le contrat
/// avec `docs/12-api-reference.md` §16 (#4060) : avant, `QuoteItemInput`
/// n'exposait que `label`+`amount_cents` et ces champs étaient silencieusement
/// ignorés côté API bien que documentés.
#[derive(Deserialize)]
pub struct QuoteItemInput {
    pub label: String,
    pub amount_cents: i64,
    pub ccam_code: Option<String>,
    pub tooth: Option<String>,
    pub amo_part_cents: Option<i64>,
    pub amc_part_cents: Option<i64>,
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
/// - `amount_cents` de chaque ligne doit être dans `]0, 100_000_000]` (1M€) → 422 sinon (#3762).
/// - `label` de chaque ligne ne doit pas être vide/blanc (trim) → 422 sinon (#3770).
/// - `deposit_pct` doit être entre 0 et 100 si fourni → 422 sinon.
/// - `ccam_code`/`tooth`/`amo_part_cents`/`amc_part_cents` optionnels par ligne,
///   persistés tels quels (#4060) ; `amo_part_cents`/`amc_part_cents` négatifs → 422.
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
    // Plafond métier réaliste (#3762) : sans borne haute, un amount_cents
    // débordant la précision de la colonne `numeric(12,2)` (quote/quote_item)
    // provoquait une erreur SQL avalée par `.map_err(|_| AppError::Internal)`
    // → 500 au lieu d'un 422 propre. 100 000 000 cents = 1 000 000,00 € par
    // ligne, largement suffisant pour un acte dentaire/médical le plus lourd.
    const MAX_ITEM_AMOUNT_CENTS: i64 = 100_000_000;
    if body
        .items
        .iter()
        .any(|i| i.amount_cents <= 0 || i.amount_cents > MAX_ITEM_AMOUNT_CENTS)
    {
        return Err(AppError::ValidationError);
    }
    // Libellé vide/blanc → 422 (#3770), comme create_prescription (prescriptions.rs)
    // et add_consultation_act : un devis présenté/signé par le patient ne doit
    // pas contenir de ligne facturable sans libellé.
    if body.items.iter().any(|i| i.label.trim().is_empty()) {
        return Err(AppError::ValidationError);
    }
    // amo_part_cents/amc_part_cents négatifs n'ont pas de sens (part prise en
    // charge) — même borne basse que amount_cents (#4060).
    if body
        .items
        .iter()
        .any(|i| i.amo_part_cents.is_some_and(|v| v < 0) || i.amc_part_cents.is_some_and(|v| v < 0))
    {
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

    // Insère les lignes. ccam_code/tooth/amo_part/amc_part alignent l'INSERT
    // sur le contrat documenté (docs/12-api-reference.md §16, #4060) — avant,
    // seuls label+unit_amount étaient persistés.
    for item in &body.items {
        sqlx::query(
            "INSERT INTO quote_item \
             (cabinet_id, quote_id, label, unit_amount, ccam_code, tooth, amo_part, amc_part) \
             VALUES ($1, $2, $3, $4::numeric / 100, $5, $6, $7::numeric / 100, $8::numeric / 100)",
        )
        .bind(claims.cabinet_id)
        .bind(quote_id)
        .bind(&item.label)
        .bind(item.amount_cents)
        .bind(&item.ccam_code)
        .bind(&item.tooth)
        .bind(item.amo_part_cents)
        .bind(item.amc_part_cents)
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
/// `panier_sante` fait exception : c'est une classification de facturation
/// (RAC 0/modéré/libre), pas une donnée clinique — obligation conventionnelle
/// de présenter l'alternative RAC 0 dans le devis (#4055/#4056). `null` si la
/// ligne n'a pas de `ccam_code` ou si l'acte n'est pas encore classifié
/// (`ccam_act.panier_sante`, #4055 : catalogue partiel, cf. #4054).
/// `amo_share_cents`/`amc_share_cents` (#4063) : ventilation du reste à
/// charge, comme `patient_share_cents` déjà exposé — un montant de
/// remboursement n'est pas une donnée clinique, le cloisonnement ci-dessus ne
/// s'y applique pas.
#[derive(Serialize)]
pub struct CabinetQuoteLineItem {
    pub id: Uuid,
    pub label: String,
    pub total_amount: i64,
    pub patient_share_cents: i64,
    pub amo_share_cents: i64,
    pub amc_share_cents: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panier_sante: Option<String>,
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
    /// Pourcentage d'acompte demandé à la création (0..100), `null` si aucun
    /// acompte imposé (#3761 : jamais exposé auparavant).
    pub deposit_pct: Option<f64>,
    /// Montant d'acompte minimum en centimes, dérivé de `deposit_pct`.
    pub deposit_amount_cents: Option<i64>,
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
                q.signed_at, q.created_at, q.deposit_pct::double precision AS deposit_pct \
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
                  AS patient_share_cents, \
                (coalesce(qi.amo_part, 0) * 100)::bigint AS amo_share_cents, \
                (coalesce(qi.amc_part, 0) * 100)::bigint AS amc_share_cents, \
                ca.panier_sante \
         FROM quote_item qi \
         LEFT JOIN ccam_act ca ON ca.code = qi.ccam_code \
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
    let deposit_pct: Option<f64> = quote_row
        .try_get("deposit_pct")
        .map_err(|_| AppError::Internal)?;
    let deposit_amount_cents =
        deposit_pct.map(|pct| ((amount_cents as f64) * pct / 100.0).ceil() as i64);

    let mut items = Vec::with_capacity(item_rows.len());
    let mut patient_share_total: i64 = 0;
    for row in &item_rows {
        let item_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let total_amount: i64 = row.try_get("total_cents").map_err(|_| AppError::Internal)?;
        let patient_share_cents: i64 = row
            .try_get("patient_share_cents")
            .map_err(|_| AppError::Internal)?;
        let amo_share_cents: i64 = row
            .try_get("amo_share_cents")
            .map_err(|_| AppError::Internal)?;
        let amc_share_cents: i64 = row
            .try_get("amc_share_cents")
            .map_err(|_| AppError::Internal)?;
        let panier_sante: Option<String> = row
            .try_get("panier_sante")
            .map_err(|_| AppError::Internal)?;
        patient_share_total += patient_share_cents;
        items.push(CabinetQuoteLineItem {
            id: item_id,
            label,
            total_amount,
            patient_share_cents,
            amo_share_cents,
            amc_share_cents,
            panier_sante,
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
        deposit_pct,
        deposit_amount_cents,
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
