//! Handlers facturation patient : GET /v1/quotes, GET /v1/quotes/:id,
//! POST /v1/quotes/:id/sign, GET /v1/payments, aliases BR5 `/v1/billing/quotes/*`.
//!
//! Refactor de taille (#4056 / CLAUDE.md plafond 700 lignes) : les handlers
//! côté cabinet (`create_cabinet_quote` et suivants) vivent dans
//! `cabinet_quotes.rs`, les PaymentIntent Stripe dans `billing_payments.rs`.
//! Aucun changement fonctionnel — mêmes handlers/contrats.
//!
//! Alias patient `/v1/billing/quotes/*` (BR5) : les handlers `billing_*` délèguent
//! aux handlers pro-existants via redirection logique (même code, alias contractuel).

use axum::extract::{Extension, Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    billing_payments::{create_payment_intent, PaymentIntentBody, PaymentIntentResponse},
    notify, pdf_text, signature_stamp, AppState, JobDispatcher,
};

/// Rôles cabinet notifiés à la signature d'un devis (#6262) : praticien +
/// secrétariat, pas tout le staff (admin/manager/doctor exclus — hors
/// périmètre de l'issue).
const QUOTE_SIGNED_NOTIFY_ROLES: [&str; 2] = ["practitioner", "secretary"];

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
    /// `provider.display_name` du praticien émetteur (#6563), `null` si le
    /// devis n'a pas de `practitioner_id` ou si ce praticien n'a pas de fiche
    /// `provider` — même source que `fetch_provider_for_response`
    /// (`appointments_response.rs`).
    pub practitioner_name: Option<String>,
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
/// Filtre optionnel `?status=`, doit être une valeur de
/// `cabinet_quotes::VALID_QUOTE_STATUSES` (draft|sent|signed|refused|expired)
/// sinon `400 invalid_status_filter` (#4276 : avant, une valeur hors énum
/// passait telle quelle en SQL et renvoyait silencieusement `{data:[]}`,
/// symétrique au fix #4066 déjà appliqué côté cabinet).
/// Pagination cursor-based (`limit` + `cursor`), tri `created_at DESC`.
/// Montants exposés en centimes entiers (`amount_cents`).
pub async fn list_quotes(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<ListQuotesQuery>,
) -> Result<Json<ListQuotesResponse>, AppError> {
    // #4276 : symétrique à cabinet_quotes::list_cabinet_quotes — une valeur
    // hors énum passait telle quelle en SQL et renvoyait silencieusement
    // `{data:[]}` au lieu de signaler l'erreur d'appel.
    if let Some(ref status) = params.status {
        if !crate::cabinet_quotes::VALID_QUOTE_STATUSES.contains(&status.as_str()) {
            return Err(AppError::InvalidQuoteStatusFilter);
        }
    }

    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let fetch_limit = limit + 1;

    let cursor = match params.cursor.as_deref() {
        Some(s) => Some(decode_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };

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
                q.currency, q.created_at, \
                practitioner_display_name(q.practitioner_id) AS practitioner_name \
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
        let practitioner_name: Option<String> = row
            .try_get("practitioner_name")
            .map_err(|_| AppError::Internal)?;

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(QuoteItem {
            id,
            status,
            total_amount_cents: amount_cents,
            currency: currency.trim().to_string(),
            created_at: created_at.to_rfc3339(),
            practitioner_name,
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
///
/// `panier_sante` (#4060) : classification 100% Santé de l'acte
/// (`ccam_act.panier_sante`, #4055), `null` si la ligne n'a pas de
/// `ccam_code` ou si l'acte n'est pas encore classifié. Contrairement à
/// `CabinetQuoteLineItem` (côté secrétariat), cette route patient expose déjà
/// `ccam_code`/`tooth` — pas de cloisonnement R.4127-72 supplémentaire ici.
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panier_sante: Option<String>,
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
    /// Pourcentage d'acompte demandé par le cabinet (0..100), `null` si aucun
    /// acompte imposé. Jamais exposé avant #3761 : le patient signait sans
    /// connaître le montant dû à `POST /v1/billing/quotes/:id/deposit`.
    pub deposit_pct: Option<f64>,
    /// Montant d'acompte minimum en centimes, dérivé de `deposit_pct` (arrondi
    /// au centime supérieur). `null` si `deposit_pct` est `null`.
    pub deposit_amount_cents: Option<i64>,
    /// Voir `QuoteItem.practitioner_name` (#6563).
    pub practitioner_name: Option<String>,
    /// PDF du devis signé dans le coffre-fort (`document.category='devis'`),
    /// posé par `sign_quote` à la transition `sent -> signed`, ou backfillé
    /// paresseusement par `get_quote` pour les devis signés avant #7046
    /// (#7068). `null` avant signature — condition du CTA « Télécharger le
    /// devis signé » côté front.
    pub document_id: Option<Uuid>,
}

/// `GET /v1/quotes/:id` — détail d'un devis du patient connecté.
///
/// Token `kind:"patient"` requis ; token pro → `403`.
/// RLS via `app.patient_account_id` (policy `quote_patient_read`, migration 0029).
/// Retourne `404` si le devis n'existe pas ou n'appartient pas au patient.
/// Backfill paresseux (#7068) : si le devis est `signed` sans `document_id`
/// (signé avant #7046), le PDF est généré ici et posé sur le devis avant
/// réponse — `enforce_quote_immutable` (migration 0265) autorise cette seule
/// mutation d'un devis déjà signé.
pub async fn get_quote(
    State(state): State<AppState>,
    Extension(object_storage): Extension<std::sync::Arc<dyn crate::ObjectStorage>>,
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
        "SELECT q.id, q.cabinet_id, q.patient_id, q.status, q.version, \
                (q.total_amount * 100)::bigint AS amount_cents, \
                q.currency, q.signed_at, q.created_at, q.updated_at, q.deposit_pct::double precision AS deposit_pct, \
                q.document_id, q.practitioner_id, \
                practitioner_display_name(q.practitioner_id) AS practitioner_name \
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
    let patient_id: Uuid = quote_row
        .try_get("patient_id")
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
                (qi.amo_part * 100)::bigint AS amo_part_cents, \
                ((qi.qty * qi.unit_amount \
                  - coalesce(qi.amo_part, 0) - coalesce(qi.amc_part, 0)) * 100)::bigint \
                  AS patient_share_cents, \
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
    let deposit_pct: Option<f64> = quote_row
        .try_get("deposit_pct")
        .map_err(|_| AppError::Internal)?;
    let practitioner_name: Option<String> = quote_row
        .try_get("practitioner_name")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Option<Uuid> = quote_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let mut document_id: Option<Uuid> = quote_row
        .try_get("document_id")
        .map_err(|_| AppError::Internal)?;

    // Backfill paresseux (#7068) : les devis signés avant #7046 n'ont jamais
    // eu de PDF généré (`sign_quote` seul posait `document_id`, uniquement à
    // la transition `sent -> signed`). On le génère ici, à la première
    // lecture, plutôt que par migration — `enforce_quote_immutable`
    // (migration 0265) autorise explicitement cette unique mutation d'un
    // devis déjà signé.
    if status == "signed" && document_id.is_none() {
        let generated_id = generate_quote_document(
            &mut tx,
            &object_storage,
            id,
            cabinet_id,
            patient_id,
            practitioner_id,
            practitioner_name.as_deref().unwrap_or("Praticien"),
            created_at,
            amount_cents,
            &currency,
            claims.sub,
        )
        .await?;

        sqlx::query(
            "UPDATE quote SET document_id = $2, updated_at = now() \
             WHERE id = $1 AND cabinet_id = $3",
        )
        .bind(id)
        .bind(generated_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        document_id = Some(generated_id);
    }

    // Journal du devis (#7176) : événement 'viewed', une entrée par lecture
    // (pas de déduplication — la timeline reflète chaque ouverture réelle
    // de l'app patient sur ce devis).
    crate::quote_events::record_quote_event(
        &mut tx,
        id,
        cabinet_id,
        "viewed",
        "patient",
        Some(claims.account_id),
        serde_json::json!({}),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut items = Vec::with_capacity(item_rows.len());
    let mut patient_share_total: i64 = 0;
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
        let panier_sante: Option<String> = row
            .try_get("panier_sante")
            .map_err(|_| AppError::Internal)?;
        let patient_share_cents: i64 = row
            .try_get("patient_share_cents")
            .map_err(|_| AppError::Internal)?;
        patient_share_total += patient_share_cents;
        items.push(QuoteLineItem {
            id: item_id,
            label,
            ccam_code,
            tooth,
            qty_cents,
            unit_amount_cents,
            amc_part_cents,
            amo_part_cents,
            panier_sante,
        });
    }

    // Acompte dérivé de la part patient nette (après AMO/AMC), pas du total
    // brut du devis — cf. cabinet_quotes.rs::get_cabinet_quote et le plancher
    // enforced sur `patient_share_cents` dans billing_payments.rs (#4583, #4610, #4611).
    let deposit_amount_cents =
        deposit_pct.map(|pct| ((patient_share_total as f64) * pct / 100.0).ceil() as i64);

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
        deposit_pct,
        deposit_amount_cents,
        practitioner_name,
        document_id,
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
/// Devis déjà `signed` → `200` idempotent avec le `signed_at` existant — y
/// compris pour le perdant d'une course (double-submit, #7015) : la ligne est
/// verrouillée `FOR UPDATE` sous scope cabinet avant la transition, le perdant
/// relit `signed` et prend la branche idempotente. Jamais de 5xx.
/// Met à jour le devis : `status = 'signed'`, `signed_at = now()`.
/// Génère le PDF du devis signé, l'uploade dans l'Object Storage et pose
/// `quote.document_id` (`document(category='devis')` — même pattern que
/// `prescriptions::sign_prescription`) : c'est ce champ que le front
/// (`quote_detail_view.dart`) attend pour afficher « Télécharger le devis
/// signé » (#7046 — jusqu'ici jamais serialisé, le CTA n'apparaissait sur
/// aucun devis).
/// Retourne `200 { signed: true, signed_at: "...ISO8601..." }` (stub Yousign — pas d'appel réel).
pub async fn sign_quote(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
    Extension(object_storage): Extension<std::sync::Arc<dyn crate::ObjectStorage>>,
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

    // Ownership résolue par la policy RLS quote_patient_read (migration 0175,
    // scope app.patient_account_id posé ci-dessus) : patient OU compte facturé
    // (billed_to_account_id, #4098) — pas de JOIN patient ici (la table
    // `patient` a sa propre RLS `patient_account_read`, migration 0029, sans
    // branche tutelle, qui éliminerait la ligne de la dépendante AVANT que la
    // clause billed_to_account_id ne puisse la sauver — cf. #5623).
    // RLS fail-closed : si le devis n'existe pas ou hors tenant → 404.
    let row = sqlx::query(
        "SELECT q.cabinet_id, q.patient_id, q.practitioner_id, q.status, q.signed_at, \
                (q.total_amount * 100)::bigint AS amount_cents, q.currency, q.created_at \
         FROM quote q \
         WHERE q.id = $1 AND q.deleted_at IS NULL",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Option<Uuid> = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
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

    let amount_cents: i64 = row
        .try_get("amount_cents")
        .map_err(|_| AppError::Internal)?;
    let currency: String = row.try_get("currency").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    // Scope cabinet pour l'UPDATE (tenant_isolation policy sur quote) et la
    // lecture des lignes du devis (tenant_isolation sur quote_item).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Verrou `FOR UPDATE` + relecture du statut (#7015). La lecture initiale
    // ci-dessus (scope patient, policy SELECT-only `quote_patient_read`) ne
    // peut pas verrouiller : `FOR UPDATE` exige aussi la policy UPDATE
    // (`tenant_isolation`), d'où le verrou posé ici, sous scope cabinet.
    // Sans lui, N double-submits lisaient tous `sent`, un seul UPDATE
    // conditionnel touchait une ligne et les N-1 autres partaient en
    // `RowNotFound` → 500. Le perdant attend le COMMIT du gagnant, relit
    // `signed` et prend la même branche idempotente (200 + `signed_at`
    // existant) qu'un second appel séquentiel. Même pattern que
    // `payment_schedules.rs` (#4311/#4573).
    let locked = sqlx::query(
        "SELECT status, signed_at FROM quote \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         FOR UPDATE",
    )
    .bind(id)
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let locked_status: String = locked.try_get("status").map_err(|_| AppError::Internal)?;
    if locked_status == "signed" {
        let existing_signed_at: Option<chrono::DateTime<chrono::Utc>> = locked
            .try_get("signed_at")
            .map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(SignQuoteResponse {
            signed: true,
            signed_at: existing_signed_at
                .map(|d| d.to_rfc3339())
                .unwrap_or_default(),
        }));
    }
    if locked_status != "sent" {
        return Err(AppError::InvalidStatus);
    }

    // Attestation d'information (#7203) : tant qu'une attestation existe
    // pour ce devis et n'est pas signée, la signature du devis lui-même est
    // refusée — le patient doit d'abord passer par
    // `POST /v1/quotes/:id/attestation/sign` (quote_attestation.rs).
    let attestation_row = sqlx::query(
        "SELECT signed_at FROM quote_information_attestation \
         WHERE quote_id = $1 AND cabinet_id = $2 \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(id)
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if let Some(row) = attestation_row {
        let signed_at: Option<chrono::DateTime<chrono::Utc>> =
            row.try_get("signed_at").map_err(|_| AppError::Internal)?;
        if signed_at.is_none() {
            return Err(AppError::AttestationNotSigned);
        }
    }

    let practitioner_row =
        sqlx::query("SELECT COALESCE(practitioner_display_name($1), 'Praticien') AS display_name")
            .bind(practitioner_id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let practitioner_name: String = practitioner_row
        .try_get("display_name")
        .map_err(|_| AppError::Internal)?;

    let document_id = generate_quote_document(
        &mut tx,
        &object_storage,
        id,
        cabinet_id,
        patient_id,
        practitioner_id,
        &practitioner_name,
        created_at,
        amount_cents,
        &currency,
        claims.sub,
    )
    .await?;

    // Transition stub Yousign : sent → signed. L'UPDATE reste conditionnel
    // (défense en profondeur derrière le verrou) ; 0 ligne = état changé
    // entre-temps → 409 déterministe (plus jamais `RowNotFound` aplati en 500).
    let update_row = sqlx::query(
        "UPDATE quote \
         SET status = 'signed', signed_at = now(), updated_at = now(), document_id = $3 \
         WHERE id = $1 AND cabinet_id = $2 AND status = 'sent' \
         RETURNING signed_at",
    )
    .bind(id)
    .bind(cabinet_id)
    .bind(document_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::InvalidStatus)?;

    let signed_at: chrono::DateTime<chrono::Utc> = update_row
        .try_get("signed_at")
        .map_err(|_| AppError::Internal)?;

    // Journal du devis (#7176) : événement 'signed', émis par le patient.
    crate::quote_events::record_quote_event(
        &mut tx,
        id,
        cabinet_id,
        "signed",
        "patient",
        Some(claims.account_id),
        serde_json::json!({}),
    )
    .await?;

    // Notifie le cabinet (#6262). Titre sans montant (anti-PII).
    let push_targets = notify::notify_cabinet_staff(
        &mut tx,
        cabinet_id,
        &QUOTE_SIGNED_NOTIFY_ROLES,
        "quote_signed",
        "Un devis a été signé",
        serde_json::json!({ "quote_id": id }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Push temps réel/mobile APRÈS commit (pattern pharmacy/orders.rs) — le
    // retour du notify était jeté, aucun push ne partait (#6329).
    for (app_user_id, notification_id) in push_targets {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }

    tracing::info!(
        account_id = %claims.account_id,
        quote_id = %id,
        document_id = %document_id,
        "quote signed"
    );

    Ok(Json(SignQuoteResponse {
        signed: true,
        signed_at: signed_at.to_rfc3339(),
    }))
}

/// Génère le PDF d'un devis signé, l'uploade dans l'Object Storage et insère
/// la ligne `document` correspondante — factorisé entre `sign_quote`
/// (transition `sent -> signed`) et le backfill paresseux de `get_quote`
/// (#7068 : reprise des devis signés avant #7046, jamais passés par ce
/// chemin). Ne touche pas `quote.document_id`, laissé à la charge de
/// l'appelant (contrainte différente selon le cas : `UPDATE` combiné à la
/// transition de statut pour l'un, `UPDATE` isolé pour l'autre).
#[allow(clippy::too_many_arguments)]
async fn generate_quote_document(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    object_storage: &std::sync::Arc<dyn crate::ObjectStorage>,
    quote_id: Uuid,
    cabinet_id: Uuid,
    patient_id: Uuid,
    practitioner_id: Option<Uuid>,
    practitioner_name: &str,
    created_at: chrono::DateTime<chrono::Utc>,
    amount_cents: i64,
    currency: &str,
    uploaded_by: Uuid,
) -> Result<Uuid, AppError> {
    // Signature/tampon du praticien (#7148) — best-effort : absents tant
    // que non téléversés ou si le devis n'a pas de praticien assigné,
    // jamais bloquant pour la génération du PDF.
    let (signature_img, stamp_img) = match practitioner_id {
        Some(pid) => {
            let provider_row = sqlx::query(
                "SELECT signature_image_id, stamp_image_id \
                 FROM provider WHERE practitioner_id = $1 AND cabinet_id = $2",
            )
            .bind(pid)
            .bind(cabinet_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;
            match provider_row {
                Some(row) => {
                    let signature_image_id: Option<Uuid> = row
                        .try_get("signature_image_id")
                        .map_err(|_| AppError::Internal)?;
                    let stamp_image_id: Option<Uuid> = row
                        .try_get("stamp_image_id")
                        .map_err(|_| AppError::Internal)?;
                    signature_stamp::load_practitioner_stamps(
                        tx,
                        object_storage.as_ref(),
                        cabinet_id,
                        signature_image_id,
                        stamp_image_id,
                    )
                    .await
                }
                None => (None, None),
            }
        }
        None => (None, None),
    };

    let patient_row = sqlx::query("SELECT first_name, last_name FROM patient WHERE id = $1")
        .bind(patient_id)
        .fetch_one(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let patient_name = format!(
        "{} {}",
        patient_row
            .try_get::<String, _>("first_name")
            .map_err(|_| AppError::Internal)?,
        patient_row
            .try_get::<String, _>("last_name")
            .map_err(|_| AppError::Internal)?
    );

    let item_rows = sqlx::query(
        "SELECT label, (qty * unit_amount * 100)::bigint AS total_cents \
         FROM quote_item WHERE quote_id = $1 ORDER BY id",
    )
    .bind(quote_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let items: Vec<(String, i64)> = item_rows
        .iter()
        .map(|r| {
            Ok::<_, AppError>((
                r.try_get("label").map_err(|_| AppError::Internal)?,
                r.try_get("total_cents").map_err(|_| AppError::Internal)?,
            ))
        })
        .collect::<Result<Vec<_>, _>>()?;

    // Même pattern que `prescriptions::sign_prescription` (#4626) : `storage_key`
    // doit référencer un objet effectivement écrit.
    let pdf_bytes = render_quote_pdf(
        quote_id,
        &patient_name,
        practitioner_name,
        created_at,
        amount_cents,
        currency,
        &items,
        signature_img.as_ref(),
        stamp_img.as_ref(),
    );
    let size_bytes = pdf_bytes.len() as i64;
    let storage_key = format!("devis/{}.pdf", quote_id);
    let filename = format!("devis-{}.pdf", quote_id);
    object_storage
        .upload(&storage_key, "application/pdf", pdf_bytes.clone())
        .await
        .map_err(|_| AppError::Internal)?;

    let doc_row = sqlx::query(
        "INSERT INTO document \
         (cabinet_id, patient_id, category, storage_key, filename, mime_type, \
          sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, 'devis', $3, $4, 'application/pdf', \
                 encode(digest($5, 'sha256'), 'hex'), 'clean', $6, $7) \
         RETURNING id",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(&storage_key)
    .bind(&filename)
    .bind(&pdf_bytes)
    .bind(uploaded_by)
    .bind(size_bytes)
    .fetch_one(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    doc_row.try_get("id").map_err(|_| AppError::Internal)
}

/// PDF minimal du devis signé (structure `%PDF-1.4` + objets + stream de
/// contenu texte), même approche que `prescriptions::render_prescription_pdf`
/// (#4626) : pas de dépendance externe (crate PDF), contenu réel et non nul
/// suffisant pour un document ouvrable par n'importe quel lecteur (taille et
/// hash réels).
#[allow(clippy::too_many_arguments)]
fn render_quote_pdf(
    quote_id: Uuid,
    patient_name: &str,
    practitioner_name: &str,
    created_at: chrono::DateTime<chrono::Utc>,
    total_amount_cents: i64,
    currency: &str,
    items: &[(String, i64)],
    signature: Option<&pdf_text::JpegImage>,
    stamp: Option<&pdf_text::JpegImage>,
) -> Vec<u8> {
    let mut lines: Vec<String> = vec![
        "Devis".to_string(),
        format!("Patient : {}", patient_name),
        format!("Praticien : {}", practitioner_name),
        format!(
            "Date : {}",
            crate::scheduling::format_paris_date(created_at)
        ),
        format!("Reference : {}", quote_id),
        String::new(),
    ];
    for (label, total_cents) in items {
        lines.push(format!(
            "{} - {:.2} {}",
            label,
            *total_cents as f64 / 100.0,
            currency
        ));
    }
    lines.push(String::new());
    lines.push(format!(
        "Total : {:.2} {}",
        total_amount_cents as f64 / 100.0,
        currency
    ));

    let mut content: Vec<u8> = b"BT /F1 12 Tf 50 780 Td 14 TL\n".to_vec();
    for line in &lines {
        content.push(b'(');
        content.extend(escape_winansi(line));
        content.extend_from_slice(b") Tj T*\n");
    }
    content.extend_from_slice(b"ET");

    // Signature/tampon du praticien (#7148) — objets XObject numérotés à
    // partir de 6 (les 5 objets ci-dessous occupent 1..=5) + opérateurs de
    // placement, hors bloc texte.
    let (stamp_objects, stamp_resources, stamp_ops) =
        pdf_text::stamp_placement(signature, stamp, 6);
    if !stamp_ops.is_empty() {
        content.push(b'\n');
        content.extend_from_slice(&stamp_ops);
    }
    let resources = if stamp_resources.is_empty() {
        "<< /Font << /F1 5 0 R >> >>".to_string()
    } else {
        format!("<< /Font << /F1 5 0 R >> /XObject <<{stamp_resources} >> >>")
    };

    let mut objects: Vec<Vec<u8>> = vec![
        b"<< /Type /Catalog /Pages 2 0 R >>".to_vec(),
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_vec(),
        format!(
            "<< /Type /Page /Parent 2 0 R /Resources {resources} \
             /MediaBox [0 0 595 842] /Contents 4 0 R >>"
        )
        .into_bytes(),
        {
            let mut obj = format!("<< /Length {} >>\nstream\n", content.len()).into_bytes();
            obj.extend_from_slice(&content);
            obj.extend_from_slice(b"\nendstream");
            obj
        },
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
            .to_vec(),
    ];
    objects.extend(stamp_objects);

    let mut pdf: Vec<u8> = b"%PDF-1.4\n".to_vec();
    let mut offsets = Vec::with_capacity(objects.len());
    for (i, obj) in objects.iter().enumerate() {
        offsets.push(pdf.len());
        pdf.extend_from_slice(format!("{} 0 obj\n", i + 1).as_bytes());
        pdf.extend_from_slice(obj);
        pdf.extend_from_slice(b"\nendobj\n");
    }
    let xref_offset = pdf.len();
    pdf.extend_from_slice(format!("xref\n0 {}\n", objects.len() + 1).as_bytes());
    pdf.extend_from_slice(b"0000000000 65535 f \n");
    for off in &offsets {
        pdf.extend_from_slice(format!("{:010} 00000 n \n", off).as_bytes());
    }
    pdf.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF",
            objects.len() + 1,
            xref_offset
        )
        .as_bytes(),
    );

    pdf
}

/// Convertit un caractère Unicode en octet WinAnsiEncoding (PDF, ~ Windows-1252).
/// `None` pour tout caractère hors de cet encodage mono-octet (translittéré en `?`
/// par l'appelant) : impossible de représenter fidèlement, mais on ne doit jamais
/// écrire de l'UTF-8 multi-octets brut dans le flux de contenu d'une police simple.
fn winansi_byte(c: char) -> Option<u8> {
    let cp = c as u32;
    match cp {
        0x00..=0x7f | 0xa0..=0xff => Some(cp as u8),
        0x20ac => Some(0x80),
        0x201a => Some(0x82),
        0x0192 => Some(0x83),
        0x201e => Some(0x84),
        0x2026 => Some(0x85),
        0x2020 => Some(0x86),
        0x2021 => Some(0x87),
        0x02c6 => Some(0x88),
        0x2030 => Some(0x89),
        0x0160 => Some(0x8a),
        0x2039 => Some(0x8b),
        0x0152 => Some(0x8c),
        0x017d => Some(0x8e),
        0x2018 => Some(0x91),
        0x2019 => Some(0x92),
        0x201c => Some(0x93),
        0x201d => Some(0x94),
        0x2022 => Some(0x95),
        0x2013 => Some(0x96),
        0x2014 => Some(0x97),
        0x02dc => Some(0x98),
        0x2122 => Some(0x99),
        0x0161 => Some(0x9a),
        0x203a => Some(0x9b),
        0x0153 => Some(0x9c),
        0x017e => Some(0x9e),
        0x0178 => Some(0x9f),
        _ => None,
    }
}

/// Échappe une chaîne pour une chaîne littérale PDF `(...)` et l'encode en
/// WinAnsiEncoding (mono-octet), cohérent avec `/Encoding /WinAnsiEncoding`
/// déclaré sur la police — sans quoi tout caractère accentué UTF-8 est rendu
/// en mojibake par un lecteur PDF (police simple = encodage mono-octet).
fn escape_winansi(s: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => out.extend_from_slice(b"\\\\"),
            '(' => out.extend_from_slice(b"\\("),
            ')' => out.extend_from_slice(b"\\)"),
            _ => out.push(winansi_byte(c).unwrap_or(b'?')),
        }
    }
    out
}

// ---------------------------------------------------------------------------
// POST /v1/billing/quotes/:id/deposit (BR5)
// Alias patient : crée un PaymentIntent de type `deposit` pour le devis.
// Délègue à `create_payment_intent` avec kind="deposit" injecté dans le body.
// ---------------------------------------------------------------------------

/// Corps de `POST /v1/billing/quotes/:id/deposit`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
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
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
    Extension(object_storage): Extension<std::sync::Arc<dyn crate::ObjectStorage>>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<SignQuoteResponse>, AppError> {
    sign_quote(
        State(state),
        Extension(dispatcher),
        Extension(object_storage),
        claims,
        Path(id),
    )
    .await
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
    pub method: Option<String>,
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
                currency, method, created_at \
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
                method: r.try_get("method").map_err(|_| AppError::Internal)?,
                created_at: created_at.to_rfc3339(),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(ListPaymentsResponse { data }))
}
