//! Devis d'officine (lot B7) — produits + prix TTC en centimes, distinct du
//! devis dentaire (`quote` : eIDAS). Ventilation AMO/AMC (#6897) : même
//! modèle déclaratif que `cabinet_quotes` (`amo_part_cents`/`amc_part_cents`
//! par ligne, saisis par la pharmacie — aucun flux réseau automatisé, cf.
//! `docs/16-decision-tiers-payant.md`), consommé par
//! `pharmacy::orders::order_from_row`.
//!
//! Espace pharmacie : `GET|POST /v1/pharmacy/quotes`, `POST …/{id}/send`,
//! `POST …/{id}/remind` (pharmacist/admin). Espace patient :
//! `GET /v1/account/pharmacy-quotes`, `POST …/{id}/accept|refuse`.

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::postgres::PgRow;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, PharmaMemberClaims, PharmaPharmacistClaims},
    notify,
    realtime::WsHub,
    AppState, JobDispatcher,
};

// ── DTO ───────────────────────────────────────────────────────────────────────

/// Un devis d'officine dans les réponses API (mêmes clés des deux bords).
#[derive(Serialize)]
pub struct QuoteDto {
    pub id: Uuid,
    pub pharmacy_id: Uuid,
    pub pharmacy_name: String,
    pub patient_display_name: String,
    pub order_id: Option<Uuid>,
    /// Statut courant de la commande d'ancrage (#6820) — un devis `accepted`
    /// peut survivre à une commande devenue `rejected`/`cancelled` (aucun
    /// mécanisme n'expire les devis déjà acceptés, à la différence des
    /// devis `sent`, cf. #6588) : le front en a besoin pour ne pas proposer
    /// « Préparer » sur un cul-de-sac. `None` si `order_id` est `None`.
    pub order_status: Option<String>,
    /// Référence courte affichable (`DEV-P-0042`), dérivée de `quote_seq`
    /// (#7141) — même pattern que `pharmacy_order.order_ref` (#6253) et
    /// `quote.quote_ref` (#6370).
    pub quote_ref: String,
    pub items: serde_json::Value,
    pub total_cents: i64,
    pub status: String,
    pub created_at: String,
    pub sent_at: Option<String>,
    pub decided_at: Option<String>,
    /// Trace de la dernière relance manuelle (#6900) — `null`/`0` tant que
    /// `remind_pharmacy_quote` n'a jamais été appelé avec succès sur ce devis.
    pub reminded_at: Option<String>,
    pub reminder_count: i32,
}

const QUOTE_COLUMNS: &str = "id, pharmacy_id, pharmacy_name, patient_display_name, order_id, \
     (SELECT po.status FROM pharmacy_order po WHERE po.id = pharmacy_quote.order_id) \
       AS order_status, \
     ('DEV-P-' || lpad(quote_seq::text, 4, '0')) AS quote_ref, \
     items, total_cents, status, created_at, sent_at, decided_at, \
     reminded_at, reminder_count";

fn quote_from_row(row: &PgRow) -> Result<QuoteDto, AppError> {
    let to_rfc3339 = |value: chrono::DateTime<chrono::Utc>| value.to_rfc3339();
    Ok(QuoteDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        pharmacy_id: row.try_get("pharmacy_id").map_err(|_| AppError::Internal)?,
        pharmacy_name: row
            .try_get("pharmacy_name")
            .map_err(|_| AppError::Internal)?,
        patient_display_name: row
            .try_get("patient_display_name")
            .map_err(|_| AppError::Internal)?,
        order_id: row.try_get("order_id").map_err(|_| AppError::Internal)?,
        order_status: row
            .try_get("order_status")
            .map_err(|_| AppError::Internal)?,
        quote_ref: row.try_get("quote_ref").map_err(|_| AppError::Internal)?,
        items: row.try_get("items").map_err(|_| AppError::Internal)?,
        total_cents: row.try_get("total_cents").map_err(|_| AppError::Internal)?,
        status: row.try_get("status").map_err(|_| AppError::Internal)?,
        created_at: to_rfc3339(row.try_get("created_at").map_err(|_| AppError::Internal)?),
        sent_at: row
            .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("sent_at")
            .map_err(|_| AppError::Internal)?
            .map(to_rfc3339),
        decided_at: row
            .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("decided_at")
            .map_err(|_| AppError::Internal)?
            .map(to_rfc3339),
        reminded_at: row
            .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("reminded_at")
            .map_err(|_| AppError::Internal)?
            .map(to_rfc3339),
        reminder_count: row
            .try_get("reminder_count")
            .map_err(|_| AppError::Internal)?,
    })
}

/// Réponse liste : `{ data: [...] }`.
#[derive(Serialize)]
pub struct QuotesResponse {
    pub data: Vec<QuoteDto>,
}

// ── Espace pharmacie ──────────────────────────────────────────────────────────

/// Une ligne du body de création.
///
/// `amo_part_cents`/`amc_part_cents` (#6897) : ventilation déclarative du
/// remboursement, saisie par la pharmacie — même mécanisme que
/// `cabinet_quotes::QuoteItemInput` (#4060 : estimation/déclaration
/// manuelle, pas de flux réseau vers un organisme, cf. `docs/16`).
/// `None`/absent → ligne non ventilée, part patient = prix de la ligne
/// (comportement historique inchangé).
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct QuoteItemInput {
    pub label: String,
    pub qty: i64,
    pub unit_price_cents: i64,
    pub amo_part_cents: Option<i64>,
    pub amc_part_cents: Option<i64>,
}

/// Body de `POST /v1/pharmacy/quotes`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateQuoteBody {
    /// Commande à laquelle rattacher le devis (l'identité patient en découle).
    pub order_id: Uuid,
    pub items: Vec<QuoteItemInput>,
}

/// `POST /v1/pharmacy/quotes` — crée un devis (statut `draft`) rattaché à une
/// commande de la pharmacie (404 hors tenant). Items vides, libellé vide,
/// quantité ou prix négatif → 422. Le total est calculé côté serveur.
/// `amo_part_cents`/`amc_part_cents` optionnels par ligne (#6897) :
/// négatifs, ou somme excédant le montant de la ligne, → 422.
/// Commande d'ancrage hors statut actif (`received`/`preparing`/`ready`) —
/// donc `picked_up`/`cancelled`/`rejected` → 409 `invalid_status` (#4415).
pub async fn create_pharmacy_quote(
    State(state): State<AppState>,
    claims: PharmaPharmacistClaims,
    Json(body): Json<CreateQuoteBody>,
) -> Result<(StatusCode, Json<QuoteDto>), AppError> {
    const MAX_QTY: i64 = 1_000_000;
    const MAX_UNIT_PRICE_CENTS: i64 = 100_000_000;

    if body.items.is_empty()
        || body.items.iter().any(|item| {
            item.label.trim().is_empty()
                || item.qty <= 0
                || item.qty > MAX_QTY
                || item.unit_price_cents < 0
                || item.unit_price_cents > MAX_UNIT_PRICE_CENTS
        })
    {
        return Err(AppError::ValidationError);
    }
    // #8155 : octet NUL non filtré dans label → échoue au bind() Postgres,
    // masqué en 500 (même défaut que #4600/#4727).
    for item in &body.items {
        crate::text_validation::reject_nul_byte(&item.label)?;
    }
    // #6897 : amo_part_cents/amc_part_cents négatifs → 422 ; leur somme ne
    // doit pas dépasser le montant de la ligne (qty * unit_price_cents),
    // sinon la part patient de la ligne deviendrait négative (même garde que
    // cabinet_quotes::validate_quote_items, #4309).
    if body.items.iter().any(|item| {
        item.amo_part_cents.is_some_and(|v| v < 0) || item.amc_part_cents.is_some_and(|v| v < 0)
    }) {
        return Err(AppError::ValidationError);
    }
    if body.items.iter().any(|item| {
        item.amo_part_cents.unwrap_or(0) + item.amc_part_cents.unwrap_or(0)
            > item.qty * item.unit_price_cents
    }) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // La commande ancre le devis : identité patient et nom dénormalisés.
    let order = sqlx::query(
        "SELECT patient_account_id, pharmacy_name, patient_display_name, status \
         FROM pharmacy_order WHERE id = $1",
    )
    .bind(body.order_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    // #4415 : une commande terminale (picked_up/cancelled/rejected) ne doit
    // plus pouvoir ancrer un nouveau devis payable — sinon un devis peut
    // être créé, envoyé, accepté et payé sur une commande jamais délivrée
    // (charge fantôme) ou déjà retirée.
    let order_status: String = order.try_get("status").map_err(|_| AppError::Internal)?;
    if !matches!(order_status.as_str(), "received" | "preparing" | "ready") {
        return Err(AppError::InvalidStatus);
    }

    let patient_account_id: Uuid = order
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;
    let pharmacy_name: String = order
        .try_get("pharmacy_name")
        .map_err(|_| AppError::Internal)?;
    let patient_display_name: String = order
        .try_get("patient_display_name")
        .map_err(|_| AppError::Internal)?;

    let total_cents: i64 = body
        .items
        .iter()
        .try_fold(0i64, |acc, item| {
            item.qty
                .checked_mul(item.unit_price_cents)
                .and_then(|line_total| acc.checked_add(line_total))
        })
        .ok_or(AppError::ValidationError)?;
    let items = serde_json::json!(body
        .items
        .iter()
        .map(|item| {
            serde_json::json!({
                "label": item.label.trim(),
                "qty": item.qty,
                "unit_price_cents": item.unit_price_cents,
                "amo_part_cents": item.amo_part_cents.unwrap_or(0),
                "amc_part_cents": item.amc_part_cents.unwrap_or(0),
            })
        })
        .collect::<Vec<_>>());

    let row = sqlx::query(&format!(
        "INSERT INTO pharmacy_quote \
         (pharmacy_id, patient_account_id, order_id, pharmacy_name, \
          patient_display_name, items, total_cents) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) \
         RETURNING {QUOTE_COLUMNS}",
    ))
    .bind(claims.pharmacy_id)
    .bind(patient_account_id)
    .bind(body.order_id)
    .bind(&pharmacy_name)
    .bind(&patient_display_name)
    .bind(&items)
    .bind(total_cents)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok((StatusCode::CREATED, Json(quote_from_row(&row)?)))
}

/// `GET /v1/pharmacy/quotes` — devis de la pharmacie (brouillons compris).
pub async fn list_pharmacy_quotes(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
) -> Result<Json<QuotesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&format!(
        "SELECT {QUOTE_COLUMNS} FROM pharmacy_quote ORDER BY created_at DESC LIMIT 200",
    ))
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(quote_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(QuotesResponse { data }))
}

/// `POST /v1/pharmacy/quotes/{id}/send` — draft → sent (pharmacist/admin).
/// Notifie le patient (sans PII) et publie sur son canal WS.
pub async fn send_pharmacy_quote(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaPharmacistClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(&format!(
        "UPDATE pharmacy_quote SET status = 'sent', sent_at = now(), updated_at = now() \
         WHERE id = $1 AND status = 'draft' \
         RETURNING {QUOTE_COLUMNS}",
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        let exists = sqlx::query("SELECT 1 FROM pharmacy_quote WHERE id = $1")
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

    let quote = quote_from_row(&row)?;

    let patient_account_id: Uuid =
        sqlx::query("SELECT patient_account_id FROM pharmacy_quote WHERE id = $1")
            .bind(id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .try_get("patient_account_id")
            .map_err(|_| AppError::Internal)?;

    // Notification patient (zéro PII — lot B4).
    let pushed = notify::notify_patient_account(
        &mut tx,
        patient_account_id,
        "pharmacy_quote_sent",
        "Un devis vous attend",
        serde_json::json!({ "pharmacy_quote_id": id, "status": "sent" }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    if let Some((app_user_id, notification_id)) = pushed {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("account_orders:{patient_account_id}"),
        serde_json::json!({
            "channel": format!("account_orders:{patient_account_id}"),
            "event": "pharmacy_quote_sent",
            "data": { "pharmacy_quote_id": id, "status": "sent" }
        })
        .to_string(),
    );

    Ok(Json(quote))
}

/// Délai minimal entre deux relances du même devis (#6900) : sans lui, un
/// triple-clic sur « Relancer » (aucun debounce réseau ne protège d'un 2e
/// clic une fois le 1er POST revenu) renotifie le patient autant de fois en
/// quelques dizaines de ms.
const REMINDER_COOLDOWN_SECS: i64 = 60;

/// `POST /v1/pharmacy/quotes/{id}/remind` — relance d'un devis déjà `sent`
/// sans réponse du patient (pharmacist/admin). Ne touche ni `status` ni
/// `sent_at` (le délai affiché côté pharmacie reste celui de l'envoi
/// d'origine) : ré-notifie seulement le patient, contrairement à
/// `send_pharmacy_quote` qui, lui, fait la transition `draft` → `sent`.
/// Trace la relance (`reminded_at`/`reminder_count`, #6900) — sans ça, la
/// réponse renvoyée était strictement identique à l'état pré-relance et
/// l'écran pharmacie n'avait rien de nouveau à afficher. Bornée par
/// [`REMINDER_COOLDOWN_SECS`] (`429 too_many_requests`) : une 2e relance
/// trop rapprochée ne ré-notifie pas le patient.
pub async fn remind_pharmacy_quote(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaPharmacistClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Verrou FOR UPDATE : sérialise avec une relance concurrente du même
    // devis, sinon deux requêtes passent toutes les deux la vérification du
    // cooldown avant que l'une des deux n'écrive `reminded_at` (#6900).
    let current = sqlx::query(
        "SELECT status, reminded_at, patient_account_id FROM pharmacy_quote \
         WHERE id = $1 FOR UPDATE",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(current) = current else {
        tx.rollback().await.ok();
        return Err(AppError::NotFound);
    };

    let status: String = current.try_get("status").map_err(|_| AppError::Internal)?;
    if status != "sent" {
        tx.rollback().await.ok();
        return Err(AppError::InvalidStatus);
    }

    let reminded_at: Option<chrono::DateTime<chrono::Utc>> = current
        .try_get("reminded_at")
        .map_err(|_| AppError::Internal)?;
    if let Some(reminded_at) = reminded_at {
        let elapsed_secs = (chrono::Utc::now() - reminded_at).num_seconds();
        if elapsed_secs < REMINDER_COOLDOWN_SECS {
            tx.rollback().await.ok();
            let retry_after = (REMINDER_COOLDOWN_SECS - elapsed_secs).max(1) as u32;
            return Err(AppError::TooManyRequests(retry_after));
        }
    }

    let row = sqlx::query(&format!(
        "UPDATE pharmacy_quote \
         SET reminded_at = now(), reminder_count = reminder_count + 1, updated_at = now() \
         WHERE id = $1 \
         RETURNING {QUOTE_COLUMNS}",
    ))
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let quote = quote_from_row(&row)?;

    let patient_account_id: Uuid = current
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;

    // Notification patient (zéro PII — même contrat que l'envoi initial).
    let pushed = notify::notify_patient_account(
        &mut tx,
        patient_account_id,
        "pharmacy_quote_reminder",
        "Un devis vous attend toujours",
        serde_json::json!({ "pharmacy_quote_id": id, "status": "sent" }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    if let Some((app_user_id, notification_id)) = pushed {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("account_orders:{patient_account_id}"),
        serde_json::json!({
            "channel": format!("account_orders:{patient_account_id}"),
            "event": "pharmacy_quote_reminder",
            "data": { "pharmacy_quote_id": id, "status": "sent" }
        })
        .to_string(),
    );

    Ok(Json(quote))
}

/// Expire les devis encore `sent` OU `draft` ancrés sur une commande qui vient
/// de sortir du cycle actif (`picked_up`/`rejected`/`cancelled`) — sinon le
/// devis `sent` reste indéfiniment ainsi alors qu'`accept`/`refuse` refusent
/// tous deux 409 `invalid_status` (garde de #4415/#5476 dans `decide_quote`),
/// sans aucune route de sortie pour le patient ni la pharmacie (#6588).
/// Couvre aussi le devis encore `draft` au moment de la transition : sans ce
/// second statut, `send_pharmacy_quote` (qui ne revérifie pas la commande)
/// pouvait plus tard faire passer un tel devis `draft` → `sent` sur une
/// commande déjà terminale, l'échouant dans le même cul-de-sac (#7277). À
/// appeler dans la même transaction que la transition de la commande.
pub(crate) async fn expire_sent_quotes_for_order(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    order_id: Uuid,
) -> Result<(), AppError> {
    sqlx::query(
        "UPDATE pharmacy_quote SET status = 'expired', decided_at = now(), updated_at = now() \
         WHERE order_id = $1 AND status IN ('sent', 'draft')",
    )
    .bind(order_id)
    .execute(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    Ok(())
}

// ── Espace patient ────────────────────────────────────────────────────────────

/// `GET /v1/account/pharmacy-quotes` — devis reçus (jamais les brouillons, RLS).
pub async fn list_account_pharmacy_quotes(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<QuotesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&format!(
        "SELECT {QUOTE_COLUMNS} FROM pharmacy_quote ORDER BY created_at DESC LIMIT 100",
    ))
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(quote_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(QuotesResponse { data }))
}

async fn decide_quote(
    state: &AppState,
    hub: &WsHub,
    dispatcher: &Arc<dyn JobDispatcher>,
    account_id: Uuid,
    id: Uuid,
    decision: &str,
) -> Result<QuoteDto, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // #4415/#5476 : la commande ancre doit rester active (received/preparing/
    // ready) au moment de la décision — sinon un devis envoyé avant un rejet
    // de commande resterait acceptable (puis payable) sur une commande jamais
    // délivrée (charge fantôme).
    let row = sqlx::query(&format!(
        "UPDATE pharmacy_quote \
         SET status = $2, decided_at = now(), updated_at = now() \
         WHERE id = $1 AND status = 'sent' \
         AND EXISTS ( \
             SELECT 1 FROM pharmacy_order po \
             WHERE po.id = pharmacy_quote.order_id \
             AND po.status IN ('received', 'preparing', 'ready') \
         ) \
         RETURNING {QUOTE_COLUMNS}",
    ))
    .bind(id)
    .bind(decision)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        let exists = sqlx::query("SELECT 1 FROM pharmacy_quote WHERE id = $1")
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

    let quote = quote_from_row(&row)?;

    // Notification du staff pharmacie — la pharmacie doit savoir que le
    // patient a décidé (symétrique de la notification patient dans
    // `send_pharmacy_quote`, jusqu'ici absente : voir #3505).
    let title = if decision == "accepted" {
        "Devis accepté par le patient"
    } else {
        "Devis refusé par le patient"
    };
    let staff = notify::notify_pharmacy_staff(
        &mut tx,
        quote.pharmacy_id,
        "pharmacy_quote_decided",
        title,
        serde_json::json!({ "pharmacy_quote_id": id, "status": decision }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    for (app_user_id, notification_id) in staff {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("pharmacy_orders:{}", quote.pharmacy_id),
        serde_json::json!({
            "channel": format!("pharmacy_orders:{}", quote.pharmacy_id),
            "event": "pharmacy_quote_decided",
            "data": { "pharmacy_quote_id": id, "status": decision }
        })
        .to_string(),
    );

    Ok(quote)
}

/// `POST /v1/account/pharmacy-quotes/{id}/accept` — sent → accepted.
/// Notifie le staff pharmacie de la décision (lot B4).
pub async fn accept_pharmacy_quote(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteDto>, AppError> {
    let quote = decide_quote(&state, &hub, &dispatcher, claims.account_id, id, "accepted").await?;
    Ok(Json(quote))
}

/// `POST /v1/account/pharmacy-quotes/{id}/refuse` — sent → refused.
/// Notifie le staff pharmacie de la décision (lot B4).
pub async fn refuse_pharmacy_quote(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteDto>, AppError> {
    let quote = decide_quote(&state, &hub, &dispatcher, claims.account_id, id, "refused").await?;
    Ok(Json(quote))
}
