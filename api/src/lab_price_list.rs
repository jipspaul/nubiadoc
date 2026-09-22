//! Handlers grille tarifaire labo (#7164, DP-F19.b), sur `lab_price_list`
//! (migration 0292, #7165) :
//! - `POST /v1/cabinet/lab-price-list/import` : import CSV
//!   `lab_name;item_label;item_code;price`.
//! - `GET /v1/cabinet/lab-price-list` : liste pour la sélection d'un produit
//!   à la commande (`lab_work_orders::create_lab_work_order`, prix
//!   pré-rempli côté client).
//!
//! Même contrat CSV « une ligne invalide n'annule pas les autres » que
//! `stock_import.rs` (#7183) — un labo avec 40 tarifs dont un mal saisi ne
//! doit pas obliger à ressaisir les 39 autres. `ON CONFLICT` sur
//! `lab_price_list_lab_item_valid_from_uniq` (cabinet_id, lab_name,
//! item_code, valid_from) : un réimport le même jour met à jour le prix au
//! lieu d'échouer sur la contrainte d'unicité.

use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

const MAX_LAB_NAME_LEN: usize = 200;
const MAX_ITEM_LABEL_LEN: usize = 300;
const MAX_ITEM_CODE_LEN: usize = 100;

/// Body de `POST /v1/cabinet/lab-price-list/import`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ImportLabPriceListBody {
    /// Contenu CSV complet, une ligne par tarif :
    /// `lab_name;item_label;item_code;price` (`price` décimal, `.` ou `,`).
    pub csv: String,
}

/// Une ligne de CSV rejetée, avec son numéro (1-based) et le motif.
#[derive(Serialize)]
pub struct LabPriceListImportLineError {
    pub line: usize,
    pub raw: String,
    pub error: String,
}

/// Une ligne de CSV importée avec succès.
#[derive(Serialize)]
pub struct LabPriceListImportedLine {
    pub line: usize,
    pub item_id: Uuid,
    pub lab_name: String,
    pub item_code: String,
    pub price_cents: i32,
}

/// Réponse de `POST /v1/cabinet/lab-price-list/import`.
#[derive(Serialize)]
pub struct LabPriceListImportResponse {
    pub imported: Vec<LabPriceListImportedLine>,
    pub errors: Vec<LabPriceListImportLineError>,
}

struct ParsedLine {
    lab_name: String,
    item_label: String,
    item_code: String,
    price_cents: i32,
}

/// Découpe une ligne `lab_name;item_label;item_code;price` — mêmes bornes de
/// longueur que le reste des libellés de la grille (`lab_price_list`,
/// migration 0292), `price` décimal positif (`.` ou `,`), converti en
/// centimes (même conversion que `stock_import::parse_line`).
fn parse_line(line: &str) -> Result<ParsedLine, &'static str> {
    let fields: Vec<&str> = line.split(';').collect();
    if fields.len() != 4 {
        return Err("colonnes_invalides");
    }
    let lab_name = fields[0].trim();
    let item_label = fields[1].trim();
    let item_code = fields[2].trim();
    let price_str = fields[3].trim();

    if lab_name.is_empty() {
        return Err("lab_name_vide");
    }
    if crate::text_validation::validate_max_len(lab_name, MAX_LAB_NAME_LEN).is_err() {
        return Err("lab_name_trop_long");
    }
    if item_label.is_empty() {
        return Err("item_label_vide");
    }
    if crate::text_validation::validate_max_len(item_label, MAX_ITEM_LABEL_LEN).is_err() {
        return Err("item_label_trop_long");
    }
    if item_code.is_empty() {
        return Err("item_code_vide");
    }
    if crate::text_validation::validate_max_len(item_code, MAX_ITEM_CODE_LEN).is_err() {
        return Err("item_code_trop_long");
    }
    if price_str.is_empty() {
        return Err("prix_invalide");
    }
    let price: f64 = price_str
        .replace(',', ".")
        .parse()
        .map_err(|_| "prix_invalide")?;
    if price < 0.0 {
        return Err("prix_invalide");
    }

    Ok(ParsedLine {
        lab_name: lab_name.to_string(),
        item_label: item_label.to_string(),
        item_code: item_code.to_string(),
        price_cents: (price * 100.0).round() as i32,
    })
}

/// `POST /v1/cabinet/lab-price-list/import` — importe la grille tarifaire
/// d'un ou plusieurs laboratoires depuis un CSV saisi/exporté à la main.
/// Chaque ligne valide crée ou met à jour (même jour, même labo, même code)
/// une ligne de `lab_price_list` avec `valid_from = CURRENT_DATE`.
pub async fn import_lab_price_list_csv(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<ImportLabPriceListBody>,
) -> Result<(StatusCode, Json<LabPriceListImportResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

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
                // Ligne d'entête tolérée ("lab_name;item_label;item_code;price"
                // littéral) : prix non numérique en première ligne → ignorée
                // silencieusement, même choix que `stock_import::import_stock_csv`.
                if line_number == 1 && error == "prix_invalide" {
                    continue;
                }
                errors.push(LabPriceListImportLineError {
                    line: line_number,
                    raw: raw_line.to_string(),
                    error: error.to_string(),
                });
                continue;
            }
        };

        if crate::text_validation::reject_nul_byte(&parsed.lab_name).is_err()
            || crate::text_validation::reject_nul_byte(&parsed.item_label).is_err()
            || crate::text_validation::reject_nul_byte(&parsed.item_code).is_err()
        {
            errors.push(LabPriceListImportLineError {
                line: line_number,
                raw: raw_line.to_string(),
                error: "caractere_invalide".to_string(),
            });
            continue;
        }

        let row = sqlx::query(
            "INSERT INTO lab_price_list \
             (cabinet_id, lab_name, item_label, item_code, price_cents, valid_from) \
             VALUES ($1, $2, $3, $4, $5, CURRENT_DATE) \
             ON CONFLICT (cabinet_id, lab_name, item_code, valid_from) \
             DO UPDATE SET item_label = EXCLUDED.item_label, price_cents = EXCLUDED.price_cents \
             RETURNING id",
        )
        .bind(claims.cabinet_id)
        .bind(&parsed.lab_name)
        .bind(&parsed.item_label)
        .bind(&parsed.item_code)
        .bind(parsed.price_cents)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let item_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

        imported.push(LabPriceListImportedLine {
            line: line_number,
            item_id,
            lab_name: parsed.lab_name,
            item_code: parsed.item_code,
            price_cents: parsed.price_cents,
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        imported = imported.len(),
        errors = errors.len(),
        "lab price list csv import processed"
    );

    Ok((
        StatusCode::OK,
        Json(LabPriceListImportResponse { imported, errors }),
    ))
}

/// Une ligne de grille tarifaire, pour la sélection d'un produit à la
/// commande (prix pré-rempli côté client).
#[derive(Serialize)]
pub struct LabPriceListItemDto {
    pub id: Uuid,
    pub lab_name: String,
    pub item_label: String,
    pub item_code: String,
    pub price_cents: i32,
    pub valid_from: String,
}

/// `GET /v1/cabinet/lab-price-list` — liste la grille tarifaire du cabinet,
/// triée par labo puis libellé, pour peupler le sélecteur de produit à la
/// création d'un bon de travail (`lab_work_orders::create_lab_work_order`).
/// Ne garde que la ligne la plus récente (`valid_from` max) par
/// `(lab_name, item_code)` — un tarif périmé ne doit pas apparaître à côté
/// de son remplaçant.
pub async fn list_lab_price_list(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<Vec<LabPriceListItemDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT DISTINCT ON (lab_name, item_code) \
                id, lab_name, item_label, item_code, price_cents, valid_from \
         FROM lab_price_list \
         WHERE cabinet_id = $1 \
         ORDER BY lab_name, item_code, valid_from DESC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut items = Vec::with_capacity(rows.len());
    for row in &rows {
        let valid_from: chrono::NaiveDate =
            row.try_get("valid_from").map_err(|_| AppError::Internal)?;
        items.push(LabPriceListItemDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            lab_name: row.try_get("lab_name").map_err(|_| AppError::Internal)?,
            item_label: row.try_get("item_label").map_err(|_| AppError::Internal)?,
            item_code: row.try_get("item_code").map_err(|_| AppError::Internal)?,
            price_cents: row.try_get("price_cents").map_err(|_| AppError::Internal)?,
            valid_from: valid_from.to_string(),
        });
    }
    items.sort_by(|a, b| (&a.lab_name, &a.item_label).cmp(&(&b.lab_name, &b.item_label)));

    Ok(Json(items))
}
