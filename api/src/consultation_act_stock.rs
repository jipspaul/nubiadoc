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

use sqlx::Row;
use uuid::Uuid;

use crate::auth::AppError;

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
    }

    Ok(())
}
