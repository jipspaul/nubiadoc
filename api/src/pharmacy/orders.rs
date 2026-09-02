//! Commandes click-and-collect (`pharmacy_order`) : partage d'ordonnance
//! cross-tenant + suivi de commande.
//!
//! Vue pharmacie : `GET /v1/pharmacy/orders[?status=]`, `GET …/{id}`,
//! `GET …/{id}/document` (URL signée du PDF), `GET …/{id}/items` (lignes de
//! l'ordonnance minimisées — #4876 : la pharmacie ne lit toujours pas les
//! tables cliniques du patient, seules les lignes `prescription_item` de la
//! commande le sont).
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
use chrono::SubsecRound;
use serde::{Deserialize, Serialize};
use sqlx::postgres::PgRow;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{
        AppError, PatientAccountClaims, PharmaMemberClaims, PharmaPharmacistClaims,
        ProSecretaryPlusClaims,
    },
    notify,
    realtime::WsHub,
    AppState, JobDispatcher, StorageSigner,
};

// ── DTO commun ────────────────────────────────────────────────────────────────

/// Une commande dans les réponses API (mêmes clés côté pharmacie et patient).
///
/// `billing_*` (#5488) : ventilation facturation du devis d'officine accepté
/// rattaché à cette commande (`pharmacy_quote`, #3312) — seule source de
/// montants existante pour une commande pharmacie (`prescription_item` ne
/// porte aucun prix). `pharmacy_quote` ne modélise pas de remboursement
/// AMO/AMC (« liste de produits, prix TTC », contrairement au devis dentaire
/// `quote`/#4063) : la part AMO/AMC est donc toujours nulle et la part
/// patient égale au total. Les 4 champs restent `None` ensemble tant
/// qu'aucun devis n'est accepté (front : gating `hasBillingSummary`).
#[derive(Serialize)]
pub struct OrderDto {
    pub id: Uuid,
    pub pharmacy_id: Uuid,
    pub pharmacy_name: String,
    /// Adresse de la pharmacie SUR LAQUELLE la commande a été passée (pas la
    /// pharmacie déclarée du compte, qui peut différer — #5645). `None` si la
    /// pharmacie n'est plus listée (RLS `pharmacy_public_read`).
    pub pharmacy_address: Option<serde_json::Value>,
    /// Téléphone de la pharmacie de la commande (bouton « Appeler la
    /// pharmacie » sur un refus, #5351) — mêmes réserves que `pharmacy_address`.
    pub pharmacy_phone: Option<String>,
    pub patient_display_name: String,
    /// Référence courte affichable (`CMD-0042`), dérivée de `order_seq`
    /// (#6253) — colonne structurante de la maquette file pharmacie.
    pub order_ref: String,
    /// Prescripteur (Dr + cabinet), snapshotés à la création (#6253) — la
    /// pharmacie ne lit jamais `practitioner`/`cabinet` en direct (RLS
    /// bornées au GUC cabinet). `None` pour les commandes créées avant
    /// #6253 dont le backfill n'a pas trouvé de profil `provider`.
    pub prescriber_name: Option<String>,
    pub prescriber_practice: Option<String>,
    pub prescription_id: Uuid,
    pub status: String,
    pub rejection_reason: Option<String>,
    pub received_at: String,
    pub updated_at: String,
    pub ready_at: Option<String>,
    pub picked_up_at: Option<String>,
    /// Nombre de lignes de l'ordonnance (#6253) — recalculé à la lecture,
    /// jamais stocké (source unique : `prescription_item`).
    pub line_count: i64,
    pub billing_total_cents: Option<i64>,
    pub billing_amo_share_cents: Option<i64>,
    pub billing_amc_share_cents: Option<i64>,
    pub billing_patient_share_cents: Option<i64>,
}

pub(crate) const ORDER_COLUMNS: &str = "id, pharmacy_id, pharmacy_name, patient_display_name, \
     prescription_id, status, rejection_reason, received_at, updated_at, ready_at, picked_up_at, \
     prescriber_name, prescriber_practice, \
     ('CMD-' || lpad(order_seq::text, 4, '0')) AS order_ref, \
     (SELECT count(*) FROM prescription_item pi \
        WHERE pi.prescription_id = pharmacy_order.prescription_id) AS line_count, \
     (SELECT pq.total_cents FROM pharmacy_quote pq WHERE pq.order_id = pharmacy_order.id \
        AND pq.status = 'accepted' ORDER BY pq.decided_at DESC LIMIT 1) AS billing_total_cents, \
     (SELECT ph.address FROM pharmacy ph WHERE ph.id = pharmacy_order.pharmacy_id) AS pharmacy_address, \
     (SELECT ph.phone FROM pharmacy ph WHERE ph.id = pharmacy_order.pharmacy_id) AS pharmacy_phone";

pub(crate) fn order_from_row(row: &PgRow) -> Result<OrderDto, AppError> {
    let to_rfc3339 = |value: chrono::DateTime<chrono::Utc>| value.to_rfc3339();
    let billing_total_cents: Option<i64> = row
        .try_get("billing_total_cents")
        .map_err(|_| AppError::Internal)?;
    Ok(OrderDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        pharmacy_id: row.try_get("pharmacy_id").map_err(|_| AppError::Internal)?,
        pharmacy_name: row
            .try_get("pharmacy_name")
            .map_err(|_| AppError::Internal)?,
        pharmacy_address: row
            .try_get("pharmacy_address")
            .map_err(|_| AppError::Internal)?,
        pharmacy_phone: row
            .try_get("pharmacy_phone")
            .map_err(|_| AppError::Internal)?,
        patient_display_name: row
            .try_get("patient_display_name")
            .map_err(|_| AppError::Internal)?,
        order_ref: row.try_get("order_ref").map_err(|_| AppError::Internal)?,
        prescriber_name: row
            .try_get("prescriber_name")
            .map_err(|_| AppError::Internal)?,
        prescriber_practice: row
            .try_get("prescriber_practice")
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
        line_count: row.try_get("line_count").map_err(|_| AppError::Internal)?,
        billing_total_cents,
        billing_amo_share_cents: billing_total_cents.map(|_| 0),
        billing_amc_share_cents: billing_total_cents.map(|_| 0),
        billing_patient_share_cents: billing_total_cents,
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

/// Paramètres de `GET /v1/account/orders` (pagination cursor-based, comme
/// `list_notifications` : `?cursor=`, `?limit=` défaut 20, max 100).
#[derive(Deserialize)]
pub struct ListAccountOrdersQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

/// Métadonnées de pagination.
#[derive(Serialize)]
pub struct OrdersPage {
    pub next_cursor: Option<String>,
}

/// Réponse de `GET /v1/account/orders` : `{ data: [...], page: { next_cursor } }`.
#[derive(Serialize)]
pub struct AccountOrdersResponse {
    pub data: Vec<OrderDto>,
    pub page: OrdersPage,
}

fn encode_order_cursor(received_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", received_at.timestamp_micros(), id)
}

fn decode_order_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
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

    // Cloisonnement cycle de vie (#3724) : cancelled/rejected éteint la base de
    // consentement partage_pharmacie de ce partage — l'accès au PDF d'ordonnance
    // doit cesser avec, pas rester accessible indéfiniment via une URL signée
    // re-générable. La RLS document_pharmacy_read (0124) borne au tenant, pas
    // au cycle de vie de la commande : filtre explicite ici.
    let row = sqlx::query(
        "SELECT o.cabinet_id, o.document_id, d.storage_key \
         FROM pharmacy_order o \
         JOIN document d ON d.id = o.document_id \
         WHERE o.id = $1 \
           AND o.status IN ('received', 'preparing', 'ready', 'picked_up')",
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

/// Une ligne d'ordonnance minimisée pour la vue pharmacie (#4876) — molécule,
/// forme, posologie, durée, quantité : rien de clinique au-delà (pas d'id,
/// pas de lien patient).
#[derive(Serialize)]
pub struct OrderItemDto {
    pub label: String,
    pub form: Option<String>,
    pub posology: String,
    pub duration: String,
    pub quantity: Option<String>,
}

/// Réponse de `GET /v1/pharmacy/orders/{id}/items`.
#[derive(Serialize)]
pub struct OrderItemsResponse {
    pub data: Vec<OrderItemDto>,
}

/// `GET /v1/pharmacy/orders/{id}/items` — lignes de l'ordonnance à délivrer
/// (#4876) : jusqu'ici la pharmacie ne pouvait lire que le PDF
/// (`get_pharmacy_order_document`) ; le métier du pharmacien (substitution,
/// posologie) exige les lignes structurées.
///
/// Même cloisonnement cycle de vie que `/document` : commande cancelled/
/// rejected → 404. RLS `prescription_item_pharmacy_read` (0227) borne aux
/// lignes des commandes de la pharmacie courante — la pharmacie ne lit
/// toujours pas `prescription` ni les autres tables cliniques.
pub async fn get_pharmacy_order_items(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<OrderItemsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let order_row = sqlx::query(
        "SELECT prescription_id FROM pharmacy_order \
         WHERE id = $1 AND status IN ('received', 'preparing', 'ready', 'picked_up')",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let prescription_id: Uuid = order_row
        .try_get("prescription_id")
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT label, form, posology, duration, quantity \
         FROM prescription_item WHERE prescription_id = $1",
    )
    .bind(prescription_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(|row| {
            Ok::<_, AppError>(OrderItemDto {
                label: row.try_get("label").map_err(|_| AppError::Internal)?,
                form: row.try_get("form").map_err(|_| AppError::Internal)?,
                posology: row.try_get("posology").map_err(|_| AppError::Internal)?,
                duration: row.try_get("duration").map_err(|_| AppError::Internal)?,
                quantity: row.try_get("quantity").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    Ok(Json(OrderItemsResponse { data }))
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
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
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
        "SELECT cabinet_id, patient_id, practitioner_id, status, document_id \
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
    let practitioner_id: Uuid = presc
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = presc.try_get("status").map_err(|_| AppError::Internal)?;
    let document_id: Option<Uuid> = presc
        .try_get("document_id")
        .map_err(|_| AppError::Internal)?;

    // GUC cabinet posé dès maintenant (pas seulement pour la transition
    // prescription plus bas) : nécessaire pour résoudre le prescripteur
    // (#6253, cf. prescriber_identity) sous les policies `tenant_isolation`
    // (cabinet) / `provider_cabinet_manage`.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Seule une ordonnance signée (PDF généré) peut partir en pharmacie.
    // `sent` reste re-commandable (ex. après annulation) — l'index unique
    // partiel bloque les doublons actifs.
    if status != "signed" && status != "sent" {
        return Err(AppError::InvalidStatus);
    }
    let document_id = document_id.ok_or(AppError::InvalidStatus)?;

    // Ordonnance déjà délivrée (une commande picked_up) → non re-commandable
    // (#3736). L'index unique partiel (0124) ne couvre que received/preparing
    // /ready ; picked_up en est volontairement exclu (une commande clôturée
    // ne bloque pas une nouvelle commande légitime après ANNULATION), mais
    // ça laissait aussi passer une re-délivrance illégitime dans une AUTRE
    // pharmacie — sans compteur ni état terminal sur la prescription.
    let already_dispensed = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(SELECT 1 FROM pharmacy_order \
         WHERE prescription_id = $1 AND status = 'picked_up')",
    )
    .bind(prescription_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if already_dispensed {
        return Err(AppError::AlreadyOrdered);
    }

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

    // Prescripteur (Dr + cabinet), snapshoté maintenant — la pharmacie ne
    // pourra plus jamais le résoudre elle-même (#6253).
    let (prescriber_name, prescriber_practice) =
        prescriber_identity(&mut tx, cabinet_id, practitioner_id).await?;

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
          created_by_kind, created_by, consent_record_id, pharmacy_name, patient_display_name, \
          prescriber_name, prescriber_practice) \
         VALUES ($1, $2, $3, $4, $5, 'patient', $6, $7, $8, $9, $10, $11) \
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
    .bind(&prescriber_name)
    .bind(&prescriber_practice)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::AlreadyOrdered
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

    let order = order_from_row(&order_row)?;

    // Notification du staff pharmacie « nouvelle commande » (lot B4).
    let staff = notify::notify_pharmacy_staff(
        &mut tx,
        body.pharmacy_id,
        "order_received",
        "Nouvelle commande reçue",
        serde_json::json!({ "order_id": order.id, "status": "received" }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    for (app_user_id, notification_id) in staff {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("pharmacy_orders:{}", body.pharmacy_id),
        notify::order_event(
            &format!("pharmacy_orders:{}", body.pharmacy_id),
            order.id,
            "received",
        ),
    );

    tracing::info!(order_id = %order.id, "pharmacy order created by patient");
    Ok((StatusCode::CREATED, Json(order)))
}

/// `GET /v1/account/orders[?cursor=][?limit=]` — commandes du patient courant.
///
/// Pagination cursor-based sur `(received_at, id)` (`?cursor=`, `?limit=`
/// défaut 20, max 100) : les comptes à historique long (suivi long terme)
/// ne peuvent plus perdre silencieusement leurs commandes au-delà d'une
/// page — auparavant `LIMIT 100` codé en dur sans paramètre accepté (#5507).
pub async fn list_account_orders(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<ListAccountOrdersQuery>,
) -> Result<Json<AccountOrdersResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let cursor = match params.cursor.as_deref() {
        Some(s) => Some(decode_order_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };

    let cursor_clause = if cursor.is_some() {
        " AND (received_at < $2 OR (received_at = $2 AND id < $3))"
    } else {
        ""
    };

    let sql = format!(
        "SELECT {ORDER_COLUMNS} FROM pharmacy_order \
         WHERE true\
         {cursor_clause} \
         ORDER BY received_at DESC, id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let fetch_limit = limit + 1;

    let rows = match cursor {
        Some((cursor_ts, cursor_id)) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_ts)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        None => sqlx::query(&sql)
            .bind(fetch_limit)
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

    let data = visible
        .iter()
        .map(order_from_row)
        .collect::<Result<Vec<_>, _>>()?;

    let next_cursor = if has_more {
        visible
            .last()
            .map(|row| -> Result<String, AppError> {
                let received_at: chrono::DateTime<chrono::Utc> =
                    row.try_get("received_at").map_err(|_| AppError::Internal)?;
                let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
                Ok(encode_order_cursor(received_at, id))
            })
            .transpose()?
    } else {
        None
    };

    Ok(Json(AccountOrdersResponse {
        data,
        page: OrdersPage { next_cursor },
    }))
}

/// Réponse de `GET /v1/account/orders/{id}` : mêmes champs que [`OrderDto`]
/// (`#[serde(flatten)]`) + `lines` — équivalent patient de
/// `get_pharmacy_order_items` (#5349, sinon la carte « Votre ordonnance »
/// front n'a jamais de données : `lines[]` toujours absent).
#[derive(Serialize)]
pub struct AccountOrderDetailDto {
    #[serde(flatten)]
    pub order: OrderDto,
    pub lines: Vec<OrderItemDto>,
}

/// `GET /v1/account/orders/{id}` — détail d'une commande du patient, lignes
/// de l'ordonnance incluses (#5349).
pub async fn get_account_order(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<AccountOrderDetailDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    // GUC patient : lecture pharmacy_order/prescription_item (policies 0108, 0109).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    // GUC compte : traversée tutelle via account_guardianship (policy 0025,
    // requise par prescription_line_patient_read étendue en 0243).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
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

    let order = order_from_row(&row)?;

    // RLS `prescription_line_patient_read` (0108, étendue par 0243) borne
    // déjà aux lignes des ordonnances du patient courant OU d'un dépendant
    // sous tutelle active, via `app.patient_account_id` et
    // `app.current_account_id` (posés ci-dessus) — même requête que
    // `get_pharmacy_order_items`.
    let item_rows = sqlx::query(
        "SELECT label, form, posology, duration, quantity \
         FROM prescription_item WHERE prescription_id = $1",
    )
    .bind(order.prescription_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let lines = item_rows
        .iter()
        .map(|row| {
            Ok::<_, AppError>(OrderItemDto {
                label: row.try_get("label").map_err(|_| AppError::Internal)?,
                form: row.try_get("form").map_err(|_| AppError::Internal)?,
                posology: row.try_get("posology").map_err(|_| AppError::Internal)?,
                duration: row.try_get("duration").map_err(|_| AppError::Internal)?,
                quantity: row.try_get("quantity").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    Ok(Json(AccountOrderDetailDto { order, lines }))
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

/// Résout le prescripteur (Dr + cabinet) à snapshoter sur la commande
/// (#6253) — `cabinet` (`tenant_isolation`) et `provider`
/// (`provider_cabinet_manage`) ne sont visibles que sous le GUC
/// `app.current_cabinet_id` du cabinet prescripteur, déjà posé par
/// l'appelant. `prescriber_name` reste `None` si le praticien n'a pas de
/// profil `provider` (`practitioner_id` optionnel côté `provider`).
pub(crate) async fn prescriber_identity(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    practitioner_id: Uuid,
) -> Result<(Option<String>, Option<String>), AppError> {
    let row = sqlx::query(
        "SELECT c.raison_sociale AS prescriber_practice, prov.display_name AS prescriber_name \
         FROM cabinet c \
         LEFT JOIN provider prov ON prov.practitioner_id = $2 \
         WHERE c.id = $1",
    )
    .bind(cabinet_id)
    .bind(practitioner_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    match row {
        Some(row) => Ok((
            row.try_get("prescriber_name")
                .map_err(|_| AppError::Internal)?,
            row.try_get("prescriber_practice")
                .map_err(|_| AppError::Internal)?,
        )),
        None => Ok((None, None)),
    }
}

// ── Machine à états (lot B3) ──────────────────────────────────────────────────

/// Applique une transition atomique côté pharmacie : `UPDATE … WHERE status =
/// ANY($expected)` — 0 ligne mise à jour = commande invisible (404) ou statut
/// invalide (409). Chaque transition est auditée dans le journal du cabinet
/// d'origine et horodatée.
struct Transition<'a> {
    order_id: Uuid,
    expected: &'a [&'a str],
    update_sql: &'a str,
    action: &'a str,
    reason: Option<&'a str>,
}

async fn pharmacy_transition(
    state: &AppState,
    hub: &Arc<WsHub>,
    dispatcher: &Arc<dyn JobDispatcher>,
    pharmacy_id: Uuid,
    actor_id: Uuid,
    t: Transition<'_>,
) -> Result<OrderDto, AppError> {
    let Transition {
        order_id,
        expected,
        update_sql,
        action,
        reason,
    } = t;
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // $3 (motif) n'existe que dans le SQL de reject — bind conditionnel.
    let mut query = sqlx::query(update_sql).bind(order_id).bind(expected);
    if let Some(reason) = reason {
        query = query.bind(reason);
    }
    let row = query
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        // Distingue 404 (hors tenant / inexistante) de 409 (mauvais statut).
        let exists = sqlx::query("SELECT 1 FROM pharmacy_order WHERE id = $1")
            .bind(order_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        tx.rollback().await.ok();
        return Err(if exists.is_none() {
            AppError::NotFound
        } else {
            AppError::InvalidStatus
        });
    };

    let order = order_from_row(&row)?;

    // Audit dans le journal du cabinet d'origine (valeurs DB, jamais client).
    let anchors =
        sqlx::query("SELECT cabinet_id, patient_account_id FROM pharmacy_order WHERE id = $1")
            .bind(order_id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = anchors
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let patient_account_id: Uuid = anchors
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'pharmacist', $3, 'pharmacy_order', $4)",
    )
    .bind(cabinet_id)
    .bind(actor_id)
    .bind(action)
    .bind(order_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Notification in-app du patient (titre générique, zéro PII — lot B4).
    let pushed = notify::notify_patient_account(
        &mut tx,
        patient_account_id,
        "order_status_changed",
        "Votre commande a été mise à jour",
        serde_json::json!({ "order_id": order_id, "status": order.status }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Push FCM + temps réel APRÈS commit (fire-and-forget, zéro PII).
    if let Some((app_user_id, notification_id)) = pushed {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("pharmacy_orders:{pharmacy_id}"),
        notify::order_event(
            &format!("pharmacy_orders:{pharmacy_id}"),
            order_id,
            &order.status,
        ),
    );
    hub.publish_named(
        &format!("account_orders:{patient_account_id}"),
        notify::order_event(
            &format!("account_orders:{patient_account_id}"),
            order_id,
            &order.status,
        ),
    );
    Ok(order)
}

/// `POST /v1/pharmacy/orders/{id}/accept` — received → preparing.
pub async fn accept_pharmacy_order(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<OrderDto>, AppError> {
    let order = pharmacy_transition(
        &state,
        &hub,
        &dispatcher,
        claims.pharmacy_id,
        claims.sub,
        Transition {
            order_id: id,
            expected: &["received"],
            update_sql: &format!(
                "UPDATE pharmacy_order \
                 SET status = 'preparing', preparing_at = now(), updated_at = now() \
                 WHERE id = $1 AND status = ANY($2) \
                 RETURNING {ORDER_COLUMNS}",
            ),
            action: "accept_pharmacy_order",
            reason: None,
        },
    )
    .await?;
    Ok(Json(order))
}

/// `POST /v1/pharmacy/orders/{id}/ready` — preparing → ready.
pub async fn ready_pharmacy_order(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<OrderDto>, AppError> {
    let order = pharmacy_transition(
        &state,
        &hub,
        &dispatcher,
        claims.pharmacy_id,
        claims.sub,
        Transition {
            order_id: id,
            expected: &["preparing"],
            update_sql: &format!(
                "UPDATE pharmacy_order \
                 SET status = 'ready', ready_at = now(), updated_at = now() \
                 WHERE id = $1 AND status = ANY($2) \
                 RETURNING {ORDER_COLUMNS}",
            ),
            action: "ready_pharmacy_order",
            reason: None,
        },
    )
    .await?;
    Ok(Json(order))
}

/// Body de `POST /v1/pharmacy/orders/{id}/reject`.
#[derive(Deserialize)]
pub struct RejectOrderBody {
    pub reason: String,
}

/// `POST /v1/pharmacy/orders/{id}/reject` — received|preparing|ready → rejected.
/// Réservé `pharmacist`/`admin` (le préparateur ne refuse pas une commande).
/// Une commande déjà `ready` non retirée doit rester rejetable (rupture de
/// stock découverte tardivement) pour libérer l'ordonnance côté patient.
/// Motif obligatoire → 422 si vide.
pub async fn reject_pharmacy_order(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaPharmacistClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<RejectOrderBody>,
) -> Result<Json<OrderDto>, AppError> {
    let reason = body.reason.trim();
    if reason.is_empty() {
        return Err(AppError::ValidationError);
    }
    let order = pharmacy_transition(
        &state,
        &hub,
        &dispatcher,
        claims.pharmacy_id,
        claims.sub,
        Transition {
            order_id: id,
            expected: &["received", "preparing", "ready"],
            update_sql: &format!(
                "UPDATE pharmacy_order \
                 SET status = 'rejected', rejection_reason = $3, updated_at = now() \
                 WHERE id = $1 AND status = ANY($2) \
                 RETURNING {ORDER_COLUMNS}",
            ),
            action: "reject_pharmacy_order",
            reason: Some(reason),
        },
    )
    .await?;
    Ok(Json(order))
}

/// `POST /v1/account/orders/{id}/cancel` — received|preparing → cancelled
/// (réservé au patient titulaire ; une commande prête n'est plus annulable).
pub async fn cancel_account_order(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
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
        "UPDATE pharmacy_order \
         SET status = 'cancelled', cancelled_at = now(), updated_at = now() \
         WHERE id = $1 AND status IN ('received', 'preparing') \
         RETURNING {ORDER_COLUMNS}",
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        let exists = sqlx::query("SELECT 1 FROM pharmacy_order WHERE id = $1")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        tx.rollback().await.ok();
        return Err(if exists.is_none() {
            AppError::NotFound
        } else {
            AppError::InvalidStatus
        });
    };

    let order = order_from_row(&row)?;

    let cabinet_id: Uuid = sqlx::query("SELECT cabinet_id FROM pharmacy_order WHERE id = $1")
        .bind(id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'cancel_pharmacy_order', 'pharmacy_order', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Notification du staff pharmacie (annulation patient — lot B4).
    let staff = notify::notify_pharmacy_staff(
        &mut tx,
        order.pharmacy_id,
        "order_status_changed",
        "Commande annulée par le patient",
        serde_json::json!({ "order_id": id, "status": "cancelled" }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    for (app_user_id, notification_id) in staff {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("pharmacy_orders:{}", order.pharmacy_id),
        notify::order_event(
            &format!("pharmacy_orders:{}", order.pharmacy_id),
            id,
            "cancelled",
        ),
    );
    hub.publish_named(
        &format!("account_orders:{}", claims.account_id),
        notify::order_event(
            &format!("account_orders:{}", claims.account_id),
            id,
            "cancelled",
        ),
    );
    Ok(Json(order))
}

// ── QR de retrait (lot B3) ────────────────────────────────────────────────────

/// Réponse de `GET /v1/account/orders/{id}/pickup-token`.
#[derive(Serialize)]
pub struct PickupTokenResponse {
    pub token: String,
    pub expires_at: String,
}

/// `GET /v1/account/orders/{id}/pickup-token` — token opaque du QR de retrait.
///
/// #3812 : un GET doit être *safe* (RFC 9110 §9.2.1) — un ré-appel ne doit
/// pas invalider le QR déjà affiché/screenshoté (re-render, retry réseau,
/// pull-to-refresh). Le token est donc dérivé de façon DÉTERMINISTE
/// (HMAC-SHA256 clé = jwt_secret, message = id||expires_at) au lieu d'un
/// tirage aléatoire : tant que `pickup_token_expires_at` en base n'a pas
/// changé, le même `(id, expires_at)` reproduit exactement le même token,
/// donc le même hash — aucune écriture DB sur un ré-appel dans la fenêtre de
/// validité. La rotation (nouveau `expires_at`, donc nouveau token) ne se
/// produit que si aucun token n'existe encore ou que le précédent a expiré.
/// Seul le hash SHA-256 du token reste stocké (`pickup_token_hash`,
/// recherché par `pickup_scan` — schéma inchangé) ; sans `jwt_secret`, un
/// accès DB seul ne permet toujours pas de reconstruire le token.
pub async fn get_pickup_token(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<PickupTokenResponse>, AppError> {
    use hmac::{Hmac, Mac};
    use sha2::{Digest, Sha256};
    type HmacSha256 = Hmac<Sha256>;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row =
        sqlx::query("SELECT status, pickup_token_expires_at FROM pharmacy_order WHERE id = $1")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        tx.rollback().await.ok();
        return Err(AppError::NotFound);
    };
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    if status != "ready" {
        tx.rollback().await.ok();
        return Err(AppError::InvalidStatus);
    }
    let existing_expires_at: Option<chrono::DateTime<chrono::Utc>> = row
        .try_get("pickup_token_expires_at")
        .map_err(|_| AppError::Internal)?;

    // Tronqué à la microseconde (#4273/QA-20260722-1) : `pickup_token_expires_at`
    // est un `timestamptz` Postgres, qui tronque déjà à la microseconde à
    // l'écriture — calculer le HMAC sur un `now()` en précision nanoseconde
    // (chrono) produit un token qui ne correspond plus à ce qui sera relu au
    // prochain appel (`existing_expires_at`, déjà tronqué), cassant la
    // stabilité du token dans sa fenêtre de validité.
    let now = chrono::Utc::now().trunc_subsecs(6);
    let expires_at = match existing_expires_at {
        Some(exp) if exp > now => exp,
        _ => now + chrono::Duration::hours(24),
    };

    let mut mac =
        HmacSha256::new_from_slice(state.jwt_secret.as_bytes()).map_err(|_| AppError::Internal)?;
    mac.update(id.to_string().as_bytes());
    mac.update(b"|");
    mac.update(expires_at.to_rfc3339().as_bytes());
    let token = hex::encode(mac.finalize().into_bytes());
    let token_hash = hex::encode(Sha256::digest(token.as_bytes()));

    // Écriture UNIQUEMENT si le token est neuf/renouvelé (expires_at a changé) —
    // un ré-appel dans la fenêtre de validité ne touche pas la DB.
    if existing_expires_at != Some(expires_at) {
        sqlx::query(
            "UPDATE pharmacy_order \
             SET pickup_token_hash = $2, pickup_token_expires_at = $3 \
             WHERE id = $1 AND status = 'ready'",
        )
        .bind(id)
        .bind(&token_hash)
        .bind(expires_at)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(Json(PickupTokenResponse {
        token,
        expires_at: expires_at.to_rfc3339(),
    }))
}

/// Body de `POST /v1/pharmacy/orders/pickup-scan`.
#[derive(Deserialize)]
pub struct PickupScanBody {
    pub token: String,
}

/// `POST /v1/pharmacy/orders/pickup-scan` — ready → picked_up via le token du
/// QR patient (scan ou saisie manuelle). Endpoint par token : le scanner ne
/// connaît que le QR.
///
/// - Token inconnu ou commande d'une autre pharmacie → 404 (anti-énumération,
///   RLS pharmacy-scoped).
/// - Statut ≠ ready → 409 `invalid_status` (double scan compris).
/// - Token expiré → 410.
/// - Succès : transition atomique single-use (`WHERE … AND status = 'ready'`).
pub async fn pickup_scan(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaMemberClaims,
    Json(body): Json<PickupScanBody>,
) -> Result<Json<OrderDto>, AppError> {
    use sha2::{Digest, Sha256};

    let token = body.token.trim();
    if token.is_empty() {
        return Err(AppError::ValidationError);
    }
    let token_hash = hex::encode(Sha256::digest(token.as_bytes()));

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(&format!(
        "UPDATE pharmacy_order \
         SET status = 'picked_up', picked_up_at = now(), picked_up_by = $2, \
             updated_at = now() \
         WHERE pickup_token_hash = $1 AND status = 'ready' \
           AND pickup_token_expires_at > now() \
         RETURNING {ORDER_COLUMNS}",
    ))
    .bind(&token_hash)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        // Diagnostic : token connu dans CE tenant ? statut ? expiration ?
        let probe = sqlx::query(
            "SELECT status, pickup_token_expires_at FROM pharmacy_order \
             WHERE pickup_token_hash = $1",
        )
        .bind(&token_hash)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        tx.rollback().await.ok();
        return Err(match probe {
            None => AppError::NotFound,
            Some(row) => {
                let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
                let expires: Option<chrono::DateTime<chrono::Utc>> = row
                    .try_get("pickup_token_expires_at")
                    .map_err(|_| AppError::Internal)?;
                if status != "ready" {
                    AppError::InvalidStatus
                } else if expires.is_some_and(|e| e <= chrono::Utc::now()) {
                    AppError::LinkExpired
                } else {
                    AppError::InvalidStatus
                }
            }
        });
    };

    let order = order_from_row(&row)?;

    let anchors =
        sqlx::query("SELECT cabinet_id, patient_account_id FROM pharmacy_order WHERE id = $1")
            .bind(order.id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = anchors
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let patient_account_id: Uuid = anchors
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'pharmacist', 'pickup_pharmacy_order', 'pharmacy_order', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(order.id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Notification patient « commande retirée » (lot B4).
    let pushed = notify::notify_patient_account(
        &mut tx,
        patient_account_id,
        "order_status_changed",
        "Votre commande a été retirée",
        serde_json::json!({ "order_id": order.id, "status": "picked_up" }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    if let Some((app_user_id, notification_id)) = pushed {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("pharmacy_orders:{}", claims.pharmacy_id),
        notify::order_event(
            &format!("pharmacy_orders:{}", claims.pharmacy_id),
            order.id,
            "picked_up",
        ),
    );
    hub.publish_named(
        &format!("account_orders:{patient_account_id}"),
        notify::order_event(
            &format!("account_orders:{patient_account_id}"),
            order.id,
            "picked_up",
        ),
    );

    tracing::info!(order_id = %order.id, "pharmacy order picked up");
    Ok(Json(order))
}
