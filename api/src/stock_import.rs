//! `POST /v1/stock/import` (#7183) : import de lignes de facture fournisseur
//! saisies à la main (CSV `ref;libellé;quantité;prix`, sans OCR) — crée les
//! `stock_item` inconnus, ajoute une réception (`stock_movement`) sur les
//! articles connus/créés, et crédite la localisation principale du cabinet
//! (`stock_locations::ensure_main_location`/`adjust_location_quantity`).
//!
//! Une ligne invalide (colonnes manquantes, quantité/prix non numérique) est
//! rapportée dans `errors` sans bloquer les lignes suivantes ni annuler
//! l'import déjà effectué — un fournisseur avec 40 lignes dont une mal
//! saisie ne doit pas obliger à ressaisir les 39 autres.

use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    stock_locations::{adjust_location_quantity, ensure_main_location},
    AppState,
};

/// Unité par défaut des articles créés par import : le format CSV
/// `ref;libellé;quantité;prix` (issue #7183) ne porte pas de colonne unité,
/// contrairement à la création manuelle (`stock_items.rs::CreateStockItemBody`).
const IMPORT_UNIT: &str = "unité";

/// Body de `POST /v1/stock/import`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ImportStockCsvBody {
    /// Contenu CSV complet, une ligne par article :
    /// `ref;libellé;quantité;prix`. `prix` optionnel (dernière colonne vide
    /// ou absente), décimal avec `.` ou `,`.
    pub csv: String,
}

/// Une ligne de CSV rejetée, avec son numéro (1-based) et le motif.
#[derive(Serialize)]
pub struct StockImportLineError {
    pub line: usize,
    pub raw: String,
    pub error: String,
}

/// Une ligne de CSV importée avec succès.
#[derive(Serialize)]
pub struct StockImportedLine {
    pub line: usize,
    pub item_id: Uuid,
    pub reference: String,
    pub quantity: i32,
}

/// Réponse de `POST /v1/stock/import`.
#[derive(Serialize)]
pub struct StockImportResponse {
    pub imported: Vec<StockImportedLine>,
    pub errors: Vec<StockImportLineError>,
}

struct ParsedLine {
    reference: String,
    label: String,
    quantity: i32,
    unit_price_cents: Option<i32>,
}

/// Découpe une ligne `ref;libellé;quantité;prix` (`prix` optionnel).
/// `quantité` doit être un entier strictement positif ; `prix`, s'il est
/// présent, un décimal positif (`.` ou `,` comme séparateur), converti en
/// centimes.
fn parse_line(line: &str) -> Result<ParsedLine, &'static str> {
    let fields: Vec<&str> = line.split(';').collect();
    if fields.len() < 3 || fields.len() > 4 {
        return Err("colonnes_invalides");
    }
    let reference = fields[0].trim();
    let label = fields[1].trim();
    let quantity_str = fields[2].trim();
    let price_str = fields.get(3).map(|s| s.trim()).unwrap_or("");

    if reference.is_empty() {
        return Err("reference_vide");
    }
    if label.is_empty() {
        return Err("libelle_vide");
    }
    let quantity: i32 = quantity_str.parse().map_err(|_| "quantite_invalide")?;
    if quantity <= 0 {
        return Err("quantite_invalide");
    }
    let unit_price_cents = if price_str.is_empty() {
        None
    } else {
        let price: f64 = price_str
            .replace(',', ".")
            .parse()
            .map_err(|_| "prix_invalide")?;
        if price < 0.0 {
            return Err("prix_invalide");
        }
        Some((price * 100.0).round() as i32)
    };

    Ok(ParsedLine {
        reference: reference.to_string(),
        label: label.to_string(),
        quantity,
        unit_price_cents,
    })
}

/// `POST /v1/stock/import` — importe une facture fournisseur saisie en CSV.
/// Chaque ligne valide crée l'article s'il n'existe pas encore dans ce
/// cabinet (référence inconnue → `unit = "unité"`) ou ajoute une réception
/// (`stock_movement`, `reason = 'reception'`) sur l'article existant, et
/// crédite la localisation principale du cabinet. `prix`, s'il est fourni,
/// met à jour `stock_item.unit_price_cents` (migration 0286).
pub async fn import_stock_csv(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<ImportStockCsvBody>,
) -> Result<(StatusCode, Json<StockImportResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let location_id = ensure_main_location(&mut tx, claims.cabinet_id).await?;

    let mut imported = Vec::new();
    let mut errors = Vec::new();

    for (idx, raw_line) in body.csv.lines().enumerate() {
        let line_number = idx + 1;
        let raw_line = raw_line.trim_end_matches('\r').trim();
        if raw_line.is_empty() {
            continue;
        }

        let parsed = match parse_line(raw_line) {
            Ok(parsed) => parsed,
            Err(error) => {
                // Ligne d'entête tolérée ("ref;libellé;quantité;prix"
                // littéral) : quantité non numérique en première ligne →
                // ignorée silencieusement plutôt que rapportée en erreur.
                if line_number == 1 && error == "quantite_invalide" {
                    continue;
                }
                errors.push(StockImportLineError {
                    line: line_number,
                    raw: raw_line.to_string(),
                    error: error.to_string(),
                });
                continue;
            }
        };

        if crate::text_validation::reject_nul_byte(&parsed.reference).is_err()
            || crate::text_validation::reject_nul_byte(&parsed.label).is_err()
        {
            errors.push(StockImportLineError {
                line: line_number,
                raw: raw_line.to_string(),
                error: "caractere_invalide".to_string(),
            });
            continue;
        }

        let existing =
            sqlx::query("SELECT id FROM stock_item WHERE cabinet_id = $1 AND reference = $2")
                .bind(claims.cabinet_id)
                .bind(&parsed.reference)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;

        let item_id: Uuid = if let Some(row) = existing {
            let item_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            sqlx::query(
                "UPDATE stock_item SET unit_price_cents = coalesce($1, unit_price_cents) \
                 WHERE id = $2 AND cabinet_id = $3",
            )
            .bind(parsed.unit_price_cents)
            .bind(item_id)
            .bind(claims.cabinet_id)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
            item_id
        } else {
            let row = sqlx::query(
                "INSERT INTO stock_item (cabinet_id, reference, label, unit, unit_price_cents) \
                 VALUES ($1, $2, $3, $4, $5) \
                 RETURNING id",
            )
            .bind(claims.cabinet_id)
            .bind(&parsed.reference)
            .bind(&parsed.label)
            .bind(IMPORT_UNIT)
            .bind(parsed.unit_price_cents)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
            row.try_get("id").map_err(|_| AppError::Internal)?
        };

        sqlx::query(
            "INSERT INTO stock_movement (cabinet_id, stock_item_id, delta, reason) \
             VALUES ($1, $2, $3, 'reception')",
        )
        .bind(claims.cabinet_id)
        .bind(item_id)
        .bind(parsed.quantity)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        sqlx::query(
            "UPDATE stock_item SET quantity_on_hand = quantity_on_hand + $1 \
             WHERE id = $2 AND cabinet_id = $3",
        )
        .bind(parsed.quantity)
        .bind(item_id)
        .bind(claims.cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        adjust_location_quantity(
            &mut tx,
            claims.cabinet_id,
            item_id,
            location_id,
            parsed.quantity,
        )
        .await?;

        imported.push(StockImportedLine {
            line: line_number,
            item_id,
            reference: parsed.reference,
            quantity: parsed.quantity,
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        imported = imported.len(),
        errors = errors.len(),
        "stock csv import processed"
    );

    Ok((
        StatusCode::OK,
        Json(StockImportResponse { imported, errors }),
    ))
}
