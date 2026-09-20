//! Décrémentation automatique du stock à la facturation d'un acte (#4145).
//!
//! `consultation_act` (migration 0042) n'avait aucun lien avec le stock —
//! facturer un acte consommateur de matériel ne décrémentait rien. À chaque
//! insertion d'un `consultation_act`, on consulte `ccam_act_stock_consumption`
//! (migration 0192, #4143) pour ce `ccam_code`/cabinet : chaque mapping trouvé
//! crée un `stock_movement` (`reason = 'consumption'`, `delta` négatif) et
//! décrémente `stock_item.quantity_on_hand` d'autant, dans la MÊME
//! transaction que l'acte (cohérence : pas d'acte facturé sans son
//! mouvement de stock, ni l'inverse). Acte sans mapping → aucun mouvement
//! créé (silencieux, comportement attendu). Stock insuffisant pour un
//! mapping → l'acte entier est refusé (`422 insufficient_stock`, #4438),
//! même garde que le mouvement manuel (`stock_items.rs`).
//!
//! Extrait de `consultation_act_create.rs` (déjà > 500 lignes, cible
//! CLAUDE.md) plutôt que d'y ajouter davantage — module dédié, une
//! responsabilité.
//!
//! #7183 (DP-F12.b) : la décrémentation ajuste aussi la localisation
//! principale du cabinet (`stock_location.is_main`, migration 0285) via
//! `stock_locations::adjust_location_quantity`, en plus de
//! `stock_item.quantity_on_hand` — la garde `insufficient_stock` (#4438)
//! reste basée sur ce dernier, inchangée ; l'ajustement par localisation,
//! lui, est planché à 0 et ne peut jamais faire échouer l'acte.

use sqlx::Row;
use uuid::Uuid;

use crate::auth::AppError;
use crate::stock_locations::{adjust_location_quantity, ensure_main_location};

/// Applique la consommation de stock mappée à `ccam_code` (s'il y en a) pour
/// l'acte `consultation_act_id` qui vient d'être inséré dans ce cabinet.
pub async fn apply_stock_consumption(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    ccam_code: &str,
    consultation_act_id: Uuid,
) -> Result<(), AppError> {
    let mappings = sqlx::query(
        "SELECT stock_item_id, quantity \
         FROM ccam_act_stock_consumption \
         WHERE cabinet_id = $1 AND ccam_code = $2",
    )
    .bind(cabinet_id)
    .bind(ccam_code)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    for row in mappings {
        let stock_item_id: Uuid = row
            .try_get("stock_item_id")
            .map_err(|_| AppError::Internal)?;
        let quantity: i32 = row.try_get("quantity").map_err(|_| AppError::Internal)?;

        // #4438 : FOR UPDATE + plancher à 0, même garde que le mouvement
        // manuel (stock_items.rs::create_stock_movement, #4341) — sinon la
        // consommation liée à un acte décrémente sans borne et produit un
        // quantity_on_hand négatif persistant, incohérent avec le chemin
        // manuel qui refuse (422 insufficient_stock) le même scénario.
        let item_row = sqlx::query(
            "SELECT quantity_on_hand FROM stock_item WHERE id = $1 AND cabinet_id = $2 FOR UPDATE",
        )
        .bind(stock_item_id)
        .bind(cabinet_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let Some(item_row) = item_row else {
            continue;
        };
        let current_quantity: i32 = item_row
            .try_get("quantity_on_hand")
            .map_err(|_| AppError::Internal)?;
        if current_quantity - quantity < 0 {
            return Err(AppError::InsufficientStock);
        }

        sqlx::query(
            "INSERT INTO stock_movement \
             (cabinet_id, stock_item_id, delta, reason, consultation_act_id) \
             VALUES ($1, $2, $3, 'consumption', $4)",
        )
        .bind(cabinet_id)
        .bind(stock_item_id)
        .bind(-quantity)
        .bind(consultation_act_id)
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

        sqlx::query(
            "UPDATE stock_item SET quantity_on_hand = quantity_on_hand - $1 \
             WHERE id = $2 AND cabinet_id = $3",
        )
        .bind(quantity)
        .bind(stock_item_id)
        .bind(cabinet_id)
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let main_location_id = ensure_main_location(tx, cabinet_id).await?;
        adjust_location_quantity(tx, cabinet_id, stock_item_id, main_location_id, -quantity)
            .await?;
    }

    Ok(())
}

/// Défait la consommation de stock appliquée par [`apply_stock_consumption`]
/// pour l'acte `consultation_act_id` qui va être supprimé (#6618).
///
/// Avant #6618, `delete_consultation_act` refusait (409 `act_linked_to_stock`)
/// dès qu'un `stock_movement` référençait l'acte : un acte consommateur de
/// stock devenait indélébile, faute de route pour défaire son mouvement. Ici,
/// pour chaque mouvement `consumption` de l'acte, on crédite `stock_item`
/// du même delta (mouvement inverse `adjustment`, traçable) puis on détache
/// le mouvement d'origine de l'acte (`consultation_act_id = NULL`) plutôt que
/// de le supprimer, pour préserver l'historique. Le détachement est
/// nécessaire : la FK composite `(consultation_act_id, cabinet_id)` de
/// `stock_movement` (migration 0192) n'a pas de clause `ON DELETE`, un
/// hard-delete de l'acte remonterait sinon en 500 (23503).
pub async fn reverse_stock_consumption(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    consultation_act_id: Uuid,
) -> Result<(), AppError> {
    let movements = sqlx::query(
        "SELECT stock_item_id, delta FROM stock_movement \
         WHERE consultation_act_id = $1 AND cabinet_id = $2 AND reason = 'consumption'",
    )
    .bind(consultation_act_id)
    .bind(cabinet_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    for row in movements {
        let stock_item_id: Uuid = row
            .try_get("stock_item_id")
            .map_err(|_| AppError::Internal)?;
        let delta: i32 = row.try_get("delta").map_err(|_| AppError::Internal)?;

        sqlx::query(
            "INSERT INTO stock_movement \
             (cabinet_id, stock_item_id, delta, reason, consultation_act_id) \
             VALUES ($1, $2, $3, 'adjustment', NULL)",
        )
        .bind(cabinet_id)
        .bind(stock_item_id)
        .bind(-delta)
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

        sqlx::query(
            "UPDATE stock_item SET quantity_on_hand = quantity_on_hand - $1 \
             WHERE id = $2 AND cabinet_id = $3",
        )
        .bind(delta)
        .bind(stock_item_id)
        .bind(cabinet_id)
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

        // `delta` est négatif (mouvement `consumption` d'origine) : créditer
        // `-delta` (positif) restaure la même quantité que
        // `adjust_location_quantity` avait débitée dans `apply_stock_consumption`.
        let main_location_id = ensure_main_location(tx, cabinet_id).await?;
        adjust_location_quantity(tx, cabinet_id, stock_item_id, main_location_id, -delta).await?;
    }

    sqlx::query(
        "UPDATE stock_movement SET consultation_act_id = NULL \
         WHERE consultation_act_id = $1 AND cabinet_id = $2",
    )
    .bind(consultation_act_id)
    .bind(cabinet_id)
    .execute(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(())
}
