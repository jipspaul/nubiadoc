//! Localisations de stock (#7183, DP-F12.b), sur `stock_location`/
//! `stock_item_location` (migration 0285, #7184) :
//! - `GET/POST /v1/cabinet/stock-locations`
//! - `DELETE /v1/cabinet/stock-locations/:id`
//! - `GET /v1/cabinet/stock-items/:id/locations` (quantité + seuil par salle)
//! - `PATCH /v1/cabinet/stock-items/:id/locations/:location_id` (seuil)
//! - `POST /v1/cabinet/stock-items/:id/transfer` (mouvement entre salles)
//!
//! `ProSecretaryPlusClaims` (secretary/practitioner/admin/manager) : même
//! périmètre que la gestion des `stock_item` (`stock_items.rs`, #4144).

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Garantit qu'une localisation `is_main` existe pour ce cabinet et renvoie
/// son id — créée à la volée (« Stock principal ») si le cabinet n'en a
/// encore aucune (cabinet créé après le backfill de la migration 0285, ou
/// n'ayant jamais eu de `stock_item` avant #7184). Appelée par le décrément
/// automatique (`consultation_act_stock.rs`) et l'import CSV
/// (`stock_import.rs`), qui doivent toujours pouvoir résoudre une
/// localisation par défaut.
pub(crate) async fn ensure_main_location(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
) -> Result<Uuid, AppError> {
    let row = sqlx::query("SELECT id FROM stock_location WHERE cabinet_id = $1 AND is_main")
        .bind(cabinet_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if let Some(row) = row {
        return row.try_get("id").map_err(|_| AppError::Internal);
    }

    let row = sqlx::query(
        "INSERT INTO stock_location (cabinet_id, name, is_main) \
         VALUES ($1, 'Stock principal', true) \
         RETURNING id",
    )
    .bind(cabinet_id)
    .fetch_one(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    row.try_get("id").map_err(|_| AppError::Internal)
}

/// Garantit qu'une ligne `stock_item_location` existe pour ce couple
/// (article, localisation), à quantité 0, avant de l'ajuster.
async fn ensure_item_location_row(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    item_id: Uuid,
    location_id: Uuid,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO stock_item_location (cabinet_id, item_id, location_id, quantity) \
         VALUES ($1, $2, $3, 0) \
         ON CONFLICT (item_id, location_id) DO NOTHING",
    )
    .bind(cabinet_id)
    .bind(item_id)
    .bind(location_id)
    .execute(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    Ok(())
}

/// Ajuste (`+=`) la quantité d'un article dans une localisation donnée,
/// planchée à 0 (jamais de quantité négative persistée, même doctrine que
/// `stock_item.quantity_on_hand`). Utilisée par le décrément automatique
/// (`consultation_act_stock.rs`) et l'import CSV (`stock_import.rs`) — pas
/// par le mouvement manuel `stock_items.rs::add_stock_movement`, qui reste
/// hors périmètre de #7183 (localisation par défaut non demandée côté saisie
/// manuelle).
pub(crate) async fn adjust_location_quantity(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    item_id: Uuid,
    location_id: Uuid,
    delta: i32,
) -> Result<(), AppError> {
    ensure_item_location_row(tx, cabinet_id, item_id, location_id).await?;
    sqlx::query(
        "UPDATE stock_item_location \
         SET quantity = GREATEST(0, quantity + $1) \
         WHERE item_id = $2 AND location_id = $3 AND cabinet_id = $4",
    )
    .bind(delta)
    .bind(item_id)
    .bind(location_id)
    .bind(cabinet_id)
    .execute(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    Ok(())
}

// ── GET/POST /v1/cabinet/stock-locations ─────────────────────────────────────

/// Une localisation de stock du cabinet.
#[derive(Serialize)]
pub struct StockLocationDto {
    pub id: Uuid,
    pub name: String,
    pub is_main: bool,
}

/// `GET /v1/cabinet/stock-locations` — liste les localisations du cabinet,
/// la principale en tête. Garantit (auto-création, [`ensure_main_location`])
/// que la principale existe déjà avant de lister — un cabinet qui n'a encore
/// jamais mouvementé de stock (pas de backfill migration 0285, pas encore
/// d'import/décrément) doit tout de même pouvoir transférer vers/depuis elle.
pub async fn list_stock_locations(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<Vec<StockLocationDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    ensure_main_location(&mut tx, claims.cabinet_id).await?;

    let rows = sqlx::query(
        "SELECT id, name, is_main \
         FROM stock_location \
         WHERE cabinet_id = $1 \
         ORDER BY is_main DESC, name",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut locations = Vec::with_capacity(rows.len());
    for row in &rows {
        locations.push(StockLocationDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            name: row.try_get("name").map_err(|_| AppError::Internal)?,
            is_main: row.try_get("is_main").map_err(|_| AppError::Internal)?,
        });
    }

    Ok(Json(locations))
}

/// Body de `POST /v1/cabinet/stock-locations`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateStockLocationBody {
    pub name: String,
}

/// Réponse de `POST /v1/cabinet/stock-locations`.
#[derive(Serialize)]
pub struct CreateStockLocationResponse {
    pub location_id: Uuid,
}

/// `POST /v1/cabinet/stock-locations` — crée une localisation secondaire
/// (salle…), jamais principale : la localisation principale est celle créée
/// par le backfill de la migration 0285 (ou par [`ensure_main_location`]).
///
/// `name` non vide → 422 sinon. `name` déjà utilisé dans ce cabinet → `409
/// stock_location_name_already_used` (index unique `(cabinet_id, name)`,
/// migration 0285).
pub async fn create_stock_location(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateStockLocationBody>,
) -> Result<(StatusCode, Json<CreateStockLocationResponse>), AppError> {
    if body.name.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    crate::text_validation::reject_nul_byte(&body.name)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO stock_location (cabinet_id, name, is_main) \
         VALUES ($1, $2, false) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.name.trim())
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::StockLocationNameAlreadyUsed
        }
        _ => AppError::Internal,
    })?;

    let location_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        location_id = %location_id,
        "stock location created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateStockLocationResponse { location_id }),
    ))
}

/// `DELETE /v1/cabinet/stock-locations/:id` — retire une localisation.
///
/// Localisation inexistante/hors tenant → 404. Localisation principale
/// (`is_main`) → `422 stock_location_is_main` (un cabinet doit toujours
/// garder une localisation par défaut). Localisation encore référencée par
/// un `stock_item_location` → `409 stock_location_in_use` (FK composite
/// `(location_id, cabinet_id)`, migration 0285 — pré-vérifié plutôt que de
/// laisser remonter la violation 23503 en 500).
pub async fn delete_stock_location(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(location_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let location_row =
        sqlx::query("SELECT is_main FROM stock_location WHERE id = $1 AND cabinet_id = $2")
            .bind(location_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let Some(location_row) = location_row else {
        return Err(AppError::NotFound);
    };
    let is_main: bool = location_row
        .try_get("is_main")
        .map_err(|_| AppError::Internal)?;
    if is_main {
        return Err(AppError::StockLocationIsMain);
    }

    let in_use = sqlx::query(
        "SELECT 1 FROM stock_item_location \
         WHERE location_id = $1 AND cabinet_id = $2 AND quantity > 0",
    )
    .bind(location_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if in_use.is_some() {
        return Err(AppError::StockLocationInUse);
    }

    // Lignes de stock à 0 : libérées avant de retirer la localisation
    // elle-même (sinon la FK composite `(location_id, cabinet_id)` refuse
    // le DELETE, 23503).
    sqlx::query("DELETE FROM stock_item_location WHERE location_id = $1 AND cabinet_id = $2")
        .bind(location_id)
        .bind(claims.cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query("DELETE FROM stock_location WHERE id = $1 AND cabinet_id = $2")
        .bind(location_id)
        .bind(claims.cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        location_id = %location_id,
        "stock location deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}

// ── GET /v1/cabinet/stock-items/:id/locations ────────────────────────────────

/// La quantité (et le seuil d'alerte) d'un article dans une localisation.
#[derive(Serialize)]
pub struct StockItemLocationDto {
    pub location_id: Uuid,
    pub location_name: String,
    pub is_main: bool,
    pub quantity: i32,
    pub threshold: Option<i32>,
}

/// `GET /v1/cabinet/stock-items/:id/locations` — stock par salle d'un
/// article : une ligne par localisation du cabinet (`LEFT JOIN`, quantité 0
/// si l'article n'y a jamais été mouvementé).
///
/// Article inexistant/hors tenant → 404.
pub async fn list_item_locations(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(item_id): Path<Uuid>,
) -> Result<Json<Vec<StockItemLocationDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let item_exists = sqlx::query("SELECT 1 FROM stock_item WHERE id = $1 AND cabinet_id = $2")
        .bind(item_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if item_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let rows = sqlx::query(
        "SELECT sl.id AS location_id, sl.name AS location_name, sl.is_main, \
                coalesce(sil.quantity, 0) AS quantity, sil.threshold \
         FROM stock_location sl \
         LEFT JOIN stock_item_location sil \
             ON sil.location_id = sl.id AND sil.item_id = $1 AND sil.cabinet_id = $2 \
         WHERE sl.cabinet_id = $2 \
         ORDER BY sl.is_main DESC, sl.name",
    )
    .bind(item_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut locations = Vec::with_capacity(rows.len());
    for row in &rows {
        locations.push(StockItemLocationDto {
            location_id: row.try_get("location_id").map_err(|_| AppError::Internal)?,
            location_name: row
                .try_get("location_name")
                .map_err(|_| AppError::Internal)?,
            is_main: row.try_get("is_main").map_err(|_| AppError::Internal)?,
            quantity: row.try_get("quantity").map_err(|_| AppError::Internal)?,
            threshold: row.try_get("threshold").map_err(|_| AppError::Internal)?,
        });
    }

    Ok(Json(locations))
}

// ── PATCH /v1/cabinet/stock-items/:id/locations/:location_id ────────────────

/// Body de `PATCH /v1/cabinet/stock-items/:id/locations/:location_id`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SetItemLocationThresholdBody {
    pub threshold: Option<i32>,
}

/// `PATCH /v1/cabinet/stock-items/:id/locations/:location_id` — fixe (ou
/// efface, `null`) le seuil d'alerte de cet article pour cette localisation
/// (distinct de `stock_item.alert_threshold`, qui reste le seuil global).
/// Crée la ligne `stock_item_location` (quantité 0) si elle n'existait pas
/// encore.
///
/// Article ou localisation inexistant/hors tenant → 404.
pub async fn set_item_location_threshold(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path((item_id, location_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<SetItemLocationThresholdBody>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let item_exists = sqlx::query("SELECT 1 FROM stock_item WHERE id = $1 AND cabinet_id = $2")
        .bind(item_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if item_exists.is_none() {
        return Err(AppError::NotFound);
    }
    let location_exists =
        sqlx::query("SELECT 1 FROM stock_location WHERE id = $1 AND cabinet_id = $2")
            .bind(location_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if location_exists.is_none() {
        return Err(AppError::NotFound);
    }

    ensure_item_location_row(&mut tx, claims.cabinet_id, item_id, location_id).await?;

    sqlx::query(
        "UPDATE stock_item_location SET threshold = $1 \
         WHERE item_id = $2 AND location_id = $3 AND cabinet_id = $4",
    )
    .bind(body.threshold)
    .bind(item_id)
    .bind(location_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        item_id = %item_id,
        location_id = %location_id,
        "stock item location threshold updated"
    );

    Ok(StatusCode::NO_CONTENT)
}

// ── POST /v1/cabinet/stock-items/:id/transfer ────────────────────────────────

/// Body de `POST /v1/cabinet/stock-items/:id/transfer`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct TransferStockBody {
    pub from_location_id: Uuid,
    pub to_location_id: Uuid,
    pub quantity: i32,
}

/// Réponse de `POST /v1/cabinet/stock-items/:id/transfer`.
#[derive(Serialize)]
pub struct TransferStockResponse {
    pub from_quantity: i32,
    pub to_quantity: i32,
}

/// `POST /v1/cabinet/stock-items/:id/transfer` — déplace `quantity` unités
/// d'un article d'une localisation à une autre du même cabinet. Ne modifie
/// pas `stock_item.quantity_on_hand` (le total du cabinet est inchangé, seule
/// sa répartition par salle bouge) et ne crée pas de `stock_movement` (le
/// ledger `stock_movement` trace les entrées/sorties du cabinet, pas les
/// déplacements internes).
///
/// `quantity` doit être strictement positif, `from_location_id` et
/// `to_location_id` doivent être distincts → 422 sinon. Article ou l'une des
/// deux localisations inexistant/hors tenant → 404. Quantité disponible dans
/// `from_location_id` insuffisante → `422 insufficient_stock` (ligne
/// verrouillée `FOR UPDATE`, même garde anti-course que
/// `stock_items.rs::add_stock_movement`, #4341).
pub async fn transfer_stock(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(item_id): Path<Uuid>,
    Json(body): Json<TransferStockBody>,
) -> Result<Json<TransferStockResponse>, AppError> {
    if body.quantity <= 0 || body.from_location_id == body.to_location_id {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let item_exists = sqlx::query("SELECT 1 FROM stock_item WHERE id = $1 AND cabinet_id = $2")
        .bind(item_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if item_exists.is_none() {
        return Err(AppError::NotFound);
    }

    for location_id in [body.from_location_id, body.to_location_id] {
        let location_exists =
            sqlx::query("SELECT 1 FROM stock_location WHERE id = $1 AND cabinet_id = $2")
                .bind(location_id)
                .bind(claims.cabinet_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        if location_exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    ensure_item_location_row(&mut tx, claims.cabinet_id, item_id, body.from_location_id).await?;

    // #4341 : FOR UPDATE verrouille la ligne pour la durée de la transaction,
    // anti-course avec un transfert/décrément concurrent sur la même paire
    // article/localisation.
    let from_row = sqlx::query(
        "SELECT quantity FROM stock_item_location \
         WHERE item_id = $1 AND location_id = $2 AND cabinet_id = $3 FOR UPDATE",
    )
    .bind(item_id)
    .bind(body.from_location_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let from_quantity: i32 = from_row
        .try_get("quantity")
        .map_err(|_| AppError::Internal)?;
    if from_quantity < body.quantity {
        return Err(AppError::InsufficientStock);
    }

    ensure_item_location_row(&mut tx, claims.cabinet_id, item_id, body.to_location_id).await?;

    let from_row = sqlx::query(
        "UPDATE stock_item_location SET quantity = quantity - $1 \
         WHERE item_id = $2 AND location_id = $3 AND cabinet_id = $4 \
         RETURNING quantity",
    )
    .bind(body.quantity)
    .bind(item_id)
    .bind(body.from_location_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let from_quantity: i32 = from_row
        .try_get("quantity")
        .map_err(|_| AppError::Internal)?;

    let to_row = sqlx::query(
        "UPDATE stock_item_location SET quantity = quantity + $1 \
         WHERE item_id = $2 AND location_id = $3 AND cabinet_id = $4 \
         RETURNING quantity",
    )
    .bind(body.quantity)
    .bind(item_id)
    .bind(body.to_location_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let to_quantity: i32 = to_row.try_get("quantity").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        item_id = %item_id,
        from_location_id = %body.from_location_id,
        to_location_id = %body.to_location_id,
        quantity = body.quantity,
        "stock transferred between locations"
    );

    Ok(Json(TransferStockResponse {
        from_quantity,
        to_quantity,
    }))
}
