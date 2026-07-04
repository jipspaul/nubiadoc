//! Commandes click-and-collect (`pharmacy_order`) : partage d'ordonnance
//! cross-tenant + suivi de commande.
//!
//! Vue pharmacie : `GET /v1/pharmacy/orders[?status=]`, `GET …/{id}`,
//! `GET …/{id}/document` (URL signée du PDF — la pharmacie ne lit jamais les
//! tables cliniques).
//! Vue patient : `POST /v1/account/prescriptions/{id}/order`,
//! `GET /v1/account/orders[/{id}]`, `GET|PUT /v1/account/pharmacy`.
//! Vue cabinet : `GET /v1/cabinet/patients/{id}/pharmacy` (présélection à
//! l'envoi d'ordonnance).

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::postgres::PgRow;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, PharmaMemberClaims, ProSecretaryPlusClaims},
    AppState, StorageSigner,
};

// ── DTO commun ────────────────────────────────────────────────────────────────

/// Une commande dans les réponses API (mêmes clés côté pharmacie et patient).
#[derive(Serialize)]
pub struct OrderDto {
    pub id: Uuid,
    pub pharmacy_id: Uuid,
    pub pharmacy_name: String,
    pub patient_display_name: String,
    pub prescription_id: Uuid,
    pub status: String,
    pub rejection_reason: Option<String>,
    pub received_at: String,
    pub updated_at: String,
    pub ready_at: Option<String>,
    pub picked_up_at: Option<String>,
}

const ORDER_COLUMNS: &str = "id, pharmacy_id, pharmacy_name, patient_display_name, \
     prescription_id, status, rejection_reason, received_at, updated_at, ready_at, picked_up_at";

pub(crate) fn order_from_row(row: &PgRow) -> Result<OrderDto, AppError> {
    let to_rfc3339 = |value: chrono::DateTime<chrono::Utc>| value.to_rfc3339();
    Ok(OrderDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        pharmacy_id: row.try_get("pharmacy_id").map_err(|_| AppError::Internal)?,
        pharmacy_name: row
            .try_get("pharmacy_name")
            .map_err(|_| AppError::Internal)?,
        patient_display_name: row
            .try_get("patient_display_name")
            .map_err(|_| AppError::Internal)?,
        prescription_id: row
            .try_get("prescription_id")
            .map_err(|_| AppError::Internal)?,
        status: row.try_get("status").map_err(|_| AppError::Internal)?,
        rejection_reason: row
            .try_get("rejection_reason")
            .map_err(|_| AppError::Internal)?,
        received_at: to_rfc3339(row.try_get("received_at").map_err(|_| AppError::Internal)?),
        updated_at: to_rfc3339(row.try_get("updated_at").map_err(|_| AppError::Internal)?),
        ready_at: row
            .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("ready_at")
            .map_err(|_| AppError::Internal)?
            .map(to_rfc3339),
        picked_up_at: row
            .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("picked_up_at")
            .map_err(|_| AppError::Internal)?
            .map(to_rfc3339),
    })
}

const VALID_STATUSES: [&str; 6] = [
    "received",
    "preparing",
    "ready",
    "picked_up",
    "rejected",
    "cancelled",
];

/// Réponse liste : `{ data: [...] }`.
#[derive(Serialize)]
pub struct OrdersResponse {
    pub data: Vec<OrderDto>,
}

// ── Vue pharmacie ─────────────────────────────────────────────────────────────

/// Paramètres de `GET /v1/pharmacy/orders`.
#[derive(Deserialize)]
pub struct ListOrdersQuery {
    pub status: Option<String>,
}

/// `GET /v1/pharmacy/orders?status=` — file des commandes de la pharmacie.
///
/// Token `kind:"pharma"` requis. RLS `pharmacy_order_pharmacy_select`.
/// Statut inconnu → 422.
pub async fn list_pharmacy_orders(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Query(params): Query<ListOrdersQuery>,
) -> Result<Json<OrdersResponse>, AppError> {
    if let Some(ref status) = params.status {
        if !VALID_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&format!(
        "SELECT {ORDER_COLUMNS} FROM pharmacy_order \
         WHERE ($1::text IS NULL OR status = $1) \
         ORDER BY received_at DESC \
         LIMIT 200",
    ))
    .bind(params.status.as_deref())
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(order_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(OrdersResponse { data }))
}

/// `GET /v1/pharmacy/orders/{id}` — détail d'une commande (404 hors tenant).
pub async fn get_pharmacy_order(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<OrderDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(&format!(
        "SELECT {ORDER_COLUMNS} FROM pharmacy_order WHERE id = $1",
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(Json(order_from_row(&row)?))
}

/// Réponse de `GET /v1/pharmacy/orders/{id}/document`.
#[derive(Serialize)]
pub struct OrderDocumentResponse {
    pub url: String,
}

/// `GET /v1/pharmacy/orders/{id}/document` — URL signée du PDF d'ordonnance.
///
/// La policy `document_pharmacy_read` (0124) borne l'accès aux documents des
/// commandes de la pharmacie. Signer indisponible → 410 `link_expired`.
/// Accès audité (`read_document`, cabinet d'origine de la commande).
pub async fn get_pharmacy_order_document(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Extension(signer): Extension<Arc<dyn StorageSigner>>,
    Path(id): Path<Uuid>,
) -> Result<Json<OrderDocumentResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT o.cabinet_id, o.document_id, d.storage_key \
         FROM pharmacy_order o \
         JOIN document d ON d.id = o.document_id \
         WHERE o.id = $1",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let document_id: Uuid = row.try_get("document_id").map_err(|_| AppError::Internal)?;
    let storage_key: String = row.try_get("storage_key").map_err(|_| AppError::Internal)?;

    let url = signer.sign(&storage_key).ok_or(AppError::LinkExpired)?;

    // Audit dans le journal du cabinet d'origine (valeur DB, jamais client).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'pharmacist', 'read_document', 'document', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(document_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(Json(OrderDocumentResponse { url }))
}

// ── Vue patient : commandes ───────────────────────────────────────────────────

/// Body de `POST /v1/account/prescriptions/{id}/order`.
#[derive(Deserialize)]
pub struct CreateOrderBody {
    pub pharmacy_id: Uuid,
}

/// `POST /v1/account/prescriptions/{id}/order` — le patient transmet son
/// ordonnance signée à une pharmacie (crée la commande, statut `received`).
///
/// - Ordonnance invisible (RLS `prescription_patient_read`) → 404.
/// - Ordonnance non signée (pas de PDF) → 409 `invalid_status`.
/// - Pharmacie inconnue ou non listée → 404.
/// - Commande active déjà existante pour cette ordonnance → 409.
/// - Consentement tracé (`consent_record`, purpose `partage_pharmacie`,
///   evidence `{channel:"in_app"}`) ; `prescription.status` → `sent`.
pub async fn create_account_order(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(prescription_id): Path<Uuid>,
    Json(body): Json<CreateOrderBody>,
) -> Result<(StatusCode, Json<OrderDto>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // GUC patient : lecture prescription/patient + insert pharmacy_order.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    // GUC compte : upsert consent_record (policies 0048).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Ordonnance visible par ce compte (policy 0109) — 404 sinon.
    let presc = sqlx::query(
        "SELECT cabinet_id, patient_id, status, document_id \
         FROM prescription WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(prescription_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = presc
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = presc
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = presc.try_get("status").map_err(|_| AppError::Internal)?;
    let document_id: Option<Uuid> = presc
        .try_get("document_id")
        .map_err(|_| AppError::Internal)?;

    // Seule une ordonnance signée (PDF généré) peut partir en pharmacie.
    // `sent` reste re-commandable (ex. après annulation) — l'index unique
    // partiel bloque les doublons actifs.
    if status != "signed" && status != "sent" {
        return Err(AppError::InvalidStatus);
    }
    let document_id = document_id.ok_or(AppError::InvalidStatus)?;

    // Pharmacie listée uniquement (policy annuaire public) — 404 sinon.
    let pharmacy = sqlx::query("SELECT raison_sociale FROM pharmacy WHERE id = $1 AND is_listed")
        .bind(body.pharmacy_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
    let pharmacy_name: String = pharmacy
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;

    // Nom minimisé pour le comptoir : « Prénom N. » (policy 0029).
    let patient_display_name = minimized_patient_name(&mut tx, patient_id).await?;

    // Consentement au partage (upsert : re-commande = renouvellement).
    let consent_row = sqlx::query(
        "INSERT INTO consent_record \
         (patient_account_id, purpose, granted, evidence) \
         VALUES ($1, 'partage_pharmacie', true, $2) \
         ON CONFLICT (patient_account_id, purpose) DO UPDATE \
         SET granted = true, granted_at = now(), revoked_at = NULL, \
             evidence = EXCLUDED.evidence \
         RETURNING id",
    )
    .bind(claims.account_id)
    .bind(serde_json::json!({"channel": "in_app", "pharmacy_id": body.pharmacy_id}))
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let consent_record_id: Uuid = consent_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Création de la commande — doublon actif → 409 (index unique partiel).
    let order_row = sqlx::query(&format!(
        "INSERT INTO pharmacy_order \
         (pharmacy_id, cabinet_id, patient_account_id, prescription_id, document_id, \
          created_by_kind, created_by, consent_record_id, pharmacy_name, patient_display_name) \
         VALUES ($1, $2, $3, $4, $5, 'patient', $6, $7, $8, $9) \
         RETURNING {ORDER_COLUMNS}",
    ))
    .bind(body.pharmacy_id)
    .bind(cabinet_id)
    .bind(claims.account_id)
    .bind(prescription_id)
    .bind(document_id)
    .bind(claims.sub)
    .bind(consent_record_id)
    .bind(&pharmacy_name)
    .bind(&patient_display_name)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::InvalidStatus
        }
        _ => AppError::Internal,
    })?;

    // Transition prescription → sent, sous le GUC du cabinet d'origine.
    // La valeur vient de la ligne DB (jamais du client) — invariant tenancy.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    sqlx::query("UPDATE prescription SET status = 'sent' WHERE id = $1")
        .bind(prescription_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Audit (journal du cabinet d'origine, zéro PII).
    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'create_pharmacy_order', 'pharmacy_order', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(order_from_row(&order_row)?.id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let order = order_from_row(&order_row)?;
    tracing::info!(order_id = %order.id, "pharmacy order created by patient");
    Ok((StatusCode::CREATED, Json(order)))
}

/// `GET /v1/account/orders` — commandes du patient courant.
pub async fn list_account_orders(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<OrdersResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&format!(
        "SELECT {ORDER_COLUMNS} FROM pharmacy_order ORDER BY received_at DESC LIMIT 100",
    ))
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;
    let data = rows
        .iter()
        .map(order_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(OrdersResponse { data }))
}

/// `GET /v1/account/orders/{id}` — détail d'une commande du patient.
pub async fn get_account_order(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<OrderDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(&format!(
        "SELECT {ORDER_COLUMNS} FROM pharmacy_order WHERE id = $1",
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(Json(order_from_row(&row)?))
}

// ── Vue patient : pharmacie déclarée ──────────────────────────────────────────

/// Une pharmacie dans les réponses « pharmacie déclarée ».
#[derive(Serialize)]
pub struct DeclaredPharmacyDto {
    pub id: Uuid,
    pub raison_sociale: String,
    pub address: serde_json::Value,
    pub phone: Option<String>,
}

/// `GET /v1/account/pharmacy` — pharmacie déclarée du patient (204 si aucune).
pub async fn get_account_pharmacy(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<axum::response::Response, AppError> {
    use axum::response::IntoResponse;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT ph.id, ph.raison_sociale, ph.address, ph.phone \
         FROM patient_account pa \
         JOIN pharmacy ph ON ph.id = pa.pharmacy_id AND ph.is_listed \
         WHERE pa.id = $1",
    )
    .bind(claims.account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    match row {
        None => Ok(StatusCode::NO_CONTENT.into_response()),
        Some(row) => Ok(Json(DeclaredPharmacyDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            raison_sociale: row
                .try_get("raison_sociale")
                .map_err(|_| AppError::Internal)?,
            address: row.try_get("address").map_err(|_| AppError::Internal)?,
            phone: row.try_get("phone").map_err(|_| AppError::Internal)?,
        })
        .into_response()),
    }
}

/// Body de `PUT /v1/account/pharmacy`.
#[derive(Deserialize)]
pub struct SetPharmacyBody {
    pub pharmacy_id: Uuid,
}

/// `PUT /v1/account/pharmacy` — déclare la pharmacie du patient.
/// Pharmacie inconnue ou non listée → 404.
pub async fn put_account_pharmacy(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<SetPharmacyBody>,
) -> Result<Json<DeclaredPharmacyDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, raison_sociale, address, phone FROM pharmacy WHERE id = $1 AND is_listed",
    )
    .bind(body.pharmacy_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    sqlx::query("UPDATE patient_account SET pharmacy_id = $1 WHERE id = $2")
        .bind(body.pharmacy_id)
        .bind(claims.account_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(DeclaredPharmacyDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        raison_sociale: row
            .try_get("raison_sociale")
            .map_err(|_| AppError::Internal)?,
        address: row.try_get("address").map_err(|_| AppError::Internal)?,
        phone: row.try_get("phone").map_err(|_| AppError::Internal)?,
    }))
}

// ── Vue cabinet : pharmacie déclarée d'un patient ─────────────────────────────

/// `GET /v1/cabinet/patients/{id}/pharmacy` — pharmacie déclarée du patient
/// (présélection à l'envoi d'ordonnance). 204 si aucune. 404 si le patient
/// n'appartient pas au cabinet (RLS, vérifié AVANT l'appel de la fonction
/// SECURITY DEFINER — anti-probing).
pub async fn get_cabinet_patient_pharmacy(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<axum::response::Response, AppError> {
    use axum::response::IntoResponse;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Le patient doit être visible dans le tenant courant (404 sinon).
    sqlx::query("SELECT 1 FROM patient WHERE id = $1 AND deleted_at IS NULL")
        .bind(patient_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let row = sqlx::query(
        "SELECT pharmacy_id, raison_sociale, address, phone \
         FROM patient_declared_pharmacy($1)",
    )
    .bind(patient_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    match row {
        None => Ok(StatusCode::NO_CONTENT.into_response()),
        Some(row) => Ok(Json(DeclaredPharmacyDto {
            id: row.try_get("pharmacy_id").map_err(|_| AppError::Internal)?,
            raison_sociale: row
                .try_get("raison_sociale")
                .map_err(|_| AppError::Internal)?,
            address: row.try_get("address").map_err(|_| AppError::Internal)?,
            phone: row.try_get("phone").map_err(|_| AppError::Internal)?,
        })
        .into_response()),
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Nom minimisé « Prénom N. » pour le comptoir (docs/07 §2.7 minimisation).
pub(crate) async fn minimized_patient_name(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_id: Uuid,
) -> Result<String, AppError> {
    let row = sqlx::query("SELECT first_name, last_name FROM patient WHERE id = $1")
        .bind(patient_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::Internal)?;
    let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
    let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
    let initial = last_name
        .chars()
        .next()
        .map(|c| format!(" {}.", c.to_uppercase()))
        .unwrap_or_default();
    Ok(format!("{first_name}{initial}"))
}
