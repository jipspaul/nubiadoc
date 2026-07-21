//! Handler `POST /v1/cabinet/consultations/:id/acts` — ajout d'un acte CCAM
//! (ou d'un groupe d'actes composé, #4115) à une séance au fauteuil.
//!
//! #4057 : bloque (409) l'ajout d'un acte invasif à risque hémorragique si
//! le dossier médical du patient mentionne un traitement anticoagulant —
//! table de correspondance v1 simple (mots-clés et liste de codes CCAM),
//! PAS un moteur d'interaction médicamenteuse. Aucune garantie
//! d'exhaustivité clinique ; sert de garde-fou minimal documenté comme tel
//! (§3.4, risque médico-légal identifié pour ce cas précis).
//!
//! #4115 : le body accepte `ccam_code` (acte unique, comportement historique)
//! OU `bundle_code` (groupe d'actes, `ccam_act_bundle`/`ccam_act_bundle_item`,
//! migration 0182) — jamais les deux. En mode bundle, un `consultation_act`
//! est créé par ligne du bundle, dans la même transaction ; le prix de
//! chaque ligne est auto-calculé depuis le tarif applicable du praticien
//! (`select_applicable_tariff`, OPTAM-aware) multiplié par `qty` — pas de
//! montant saisi manuellement pour ce mode, donc pas d'avertissement de
//! sous-cotation (rien à comparer à une saisie humaine).
//!
//! Extrait de `consultation_acts.rs` (refactor de taille, CLAUDE.md plafond
//! 700 lignes — `consultation_acts.rs` approchait la limite avant l'ajout
//! de #4115) — module autonome.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    ccam_acts::select_applicable_tariff,
    medical_record::decrypt_stub,
    AppState,
};

/// Seuil de sous-cotation (#4162, Pilier 5 §4.2) : un `amount_cents` saisi
/// sous 80% du tarif de référence applicable (`select_applicable_tariff`,
/// OPTAM-aware) déclenche un avertissement NON BLOQUANT dans la réponse.
/// Seuil produit choisi (non spécifié par l'issue) — 20% en-dessous reste au
/// pouvoir d'appréciation du praticien (dépassement d'honoraires négatif
/// légitime dans certains cas), l'objectif est d'attirer l'attention sur une
/// saisie probablement erronée (faute de frappe, oubli d'un zéro), pas de
/// bloquer une décision tarifaire assumée.
const UNDERQUOTE_WARNING_THRESHOLD_PCT: f64 = 0.20;

/// Mots-clés (sous-chaînes, recherche insensible à la casse) indiquant un
/// traitement anticoagulant dans `medical_record.treatments` (#4057, v1).
/// Liste non exhaustive — anticoagulants oraux directs + AVK les plus
/// courants en France. À enrichir/remplacer par un référentiel médicamenteux
/// structuré (ex. base Vidal/ANSM) dans une version ultérieure.
const ANTICOAGULANT_KEYWORDS: &[&str] = &[
    "anticoagul",
    "warfarine",
    "previscan",
    "sintrom",
    "xarelto",
    "eliquis",
    "pradaxa",
    "coumadine",
    "fluindione",
];

/// Codes CCAM considérés invasifs/à risque hémorragique (avulsions, chirurgie
/// osseuse, surfaçage radiculaire, gingivectomie) — table de correspondance
/// v1 simple (#4057), volontairement restreinte aux actes du catalogue
/// `ccam_act` seedé (migration 0119) les plus manifestement à risque.
const RISKY_CCAM_CODES_UNDER_ANTICOAGULANTS: &[&str] = &[
    "HBLD724", // Avulsion d'une dent permanente sur arcade
    "HBGD047", // Avulsion de dent de sagesse incluse
    "HBBD002", // Greffe osseuse pré-implantaire
    "HBFD001", // Surfaçage radiculaire, un sextant
    "HBFD002", // Gingivectomie, un sextant
    "HBLD001", // Pose d'un implant dentaire
];

/// `true` si le JSON `treatments` (tel que stocké par `medical_record.rs`,
/// `Vec<serde_json::Value>` libre) contient un mot-clé anticoagulant connu.
/// Représentation JSON entière convertie en texte pour matcher aussi bien
/// des entrées chaînes (`"Warfarine"`) que des objets (`{"name": "..."}`)
/// sans imposer un schéma strict à `treatments`.
fn treatments_mention_anticoagulants(treatments: &serde_json::Value) -> bool {
    let text = treatments.to_string().to_lowercase();
    ANTICOAGULANT_KEYWORDS.iter().any(|kw| text.contains(kw))
}

/// Corps de la requête `POST /v1/cabinet/consultations/:id/acts` — soit
/// `ccam_code` (acte unique), soit `bundle_code` (groupe, #4115), jamais
/// les deux, jamais aucun des deux → 422.
#[derive(Deserialize)]
pub struct AddActBody {
    pub ccam_code: Option<String>,
    pub bundle_code: Option<String>,
    /// Requis si `ccam_code` fourni. Ignoré en mode `bundle_code` (chaque
    /// ligne reprend le libellé du catalogue `ccam_act`).
    pub label: Option<String>,
    pub tooth: Option<String>,
    /// Requis/utilisé seulement en mode `ccam_code` — en mode `bundle_code`
    /// le montant de chaque ligne est auto-calculé (voir doc de module).
    pub amount_cents: Option<i32>,
    /// Code acte sécurité sociale — accepté, non stocké (pas de colonne dédiée dans cette version).
    #[allow(dead_code)]
    pub secu_code: Option<String>,
    /// Réservé pour le devis (inclus/hors-nomenclature) — accepté, non stocké dans cette version.
    #[allow(dead_code)]
    pub included: Option<bool>,
}

/// Un acte créé (élément de la réponse, seul ou dans un groupe).
#[derive(Serialize)]
pub struct AddActResponse {
    pub act_id: Uuid,
    /// Avertissement de sous-cotation (#4162) — NON bloquant, l'acte est créé
    /// normalement. `null` si `amount_cents` absent/nul, code CCAM inconnu du
    /// référentiel, montant saisi au-dessus du seuil, ou acte auto-tarifé
    /// (mode `bundle_code`, rien à comparer à une saisie humaine).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warning: Option<String>,
}

/// Réponse de `POST /v1/cabinet/consultations/:id/acts` — un objet acte
/// unique (mode `ccam_code`, contrat historique inchangé) ou `{"acts": [...]}`
/// (mode `bundle_code`, #4115).
#[derive(Serialize)]
#[serde(untagged)]
pub enum AddActApiResponse {
    Single(AddActResponse),
    Bundle { acts: Vec<AddActResponse> },
}

/// Praticien appelant est-il adhérent OPTAM (#4056) ? Lu une seule fois par
/// requête, réutilisé pour chaque ligne en mode bundle.
async fn is_optam_practitioner(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    practitioner_id: Uuid,
    cabinet_id: Uuid,
) -> Result<bool, AppError> {
    let optam_row =
        sqlx::query("SELECT conventions FROM practitioner WHERE id = $1 AND cabinet_id = $2")
            .bind(practitioner_id)
            .bind(cabinet_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;
    Ok(optam_row
        .and_then(|r| r.try_get::<serde_json::Value, _>("conventions").ok())
        .and_then(|c| c.get("optam").and_then(serde_json::Value::as_bool))
        .unwrap_or(false))
}

/// Tarif applicable au praticien pour ce code CCAM (`None` si le code n'est
/// pas au référentiel).
async fn applicable_tariff_for(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    ccam_code: &str,
    is_optam: bool,
) -> Result<Option<i32>, AppError> {
    let tariff_row = sqlx::query(
        "SELECT tarif_cents, secteur1_cents, optam_cents FROM ccam_act WHERE code = $1",
    )
    .bind(ccam_code)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(tariff_row.and_then(|row| {
        let tarif_cents: Option<i32> = row.try_get("tarif_cents").ok();
        let secteur1_cents: Option<i32> = row.try_get("secteur1_cents").ok();
        let optam_cents: Option<i32> = row.try_get("optam_cents").ok();
        select_applicable_tariff(is_optam, tarif_cents, secteur1_cents, optam_cents)
    }))
}

/// Insère une ligne `consultation_act`, avec la garde clinique anticoagulants
/// (#4057) et, si `entered_amount_cents` est fourni (mode `ccam_code` avec
/// montant saisi), l'avertissement de sous-cotation (#4162). En mode bundle,
/// `entered_amount_cents` est `None` : le montant vient directement de
/// `final_amount_cents` (déjà auto-calculé par l'appelant), sans avertissement.
#[allow(clippy::too_many_arguments)]
async fn insert_one_act(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    appointment_id: Uuid,
    patient_id: Uuid,
    practitioner_id: Uuid,
    ccam_code: &str,
    label: &str,
    tooth: Option<&str>,
    final_amount_cents: i32,
    entered_amount_cents: Option<i32>,
    is_optam: bool,
) -> Result<AddActResponse, AppError> {
    // Alerte clinique bloquante (#4057) : acte invasif + patient sous
    // anticoagulants d'après le dossier médical → 409, pas d'insertion.
    if RISKY_CCAM_CODES_UNDER_ANTICOAGULANTS.contains(&ccam_code) {
        let record_row = sqlx::query(
            "SELECT data_ciphertext FROM medical_record \
             WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
             ORDER BY updated_at DESC LIMIT 1",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let at_risk = record_row
            .and_then(|row| row.try_get::<Option<Vec<u8>>, _>("data_ciphertext").ok())
            .flatten()
            .and_then(|ct| decrypt_stub(&ct))
            .is_some_and(|data| treatments_mention_anticoagulants(&data["treatments"]));

        if at_risk {
            return Err(AppError::ClinicalRiskWarning(format!(
                "Patient sous anticoagulants (dossier médical) — vérifier le \
                 risque hémorragique avant l'acte {ccam_code} (invasif)."
            )));
        }
    }

    // Avertissement de sous-cotation (#4162) — seulement pour un montant
    // saisi manuellement (mode ccam_code), jamais pour un montant auto-calculé.
    let warning = if let Some(entered) = entered_amount_cents.filter(|c| *c > 0) {
        applicable_tariff_for(tx, ccam_code, is_optam)
            .await?
            .and_then(|applicable| {
                let threshold = (f64::from(applicable) * (1.0 - UNDERQUOTE_WARNING_THRESHOLD_PCT))
                    .round() as i32;
                if entered < threshold {
                    Some(format!(
                        "Montant saisi ({:.2} €) significativement inférieur au tarif de \
                         référence ({:.2} €) pour l'acte {ccam_code}.",
                        f64::from(entered) / 100.0,
                        f64::from(applicable) / 100.0,
                    ))
                } else {
                    None
                }
            })
    } else {
        None
    };

    let act_row = sqlx::query(
        "INSERT INTO consultation_act \
         (cabinet_id, appointment_id, patient_id, practitioner_id, \
          ccam_code, label, tooth, amount_cents) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) \
         RETURNING id",
    )
    .bind(cabinet_id)
    .bind(appointment_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(ccam_code)
    .bind(label)
    .bind(tooth)
    .bind(final_amount_cents)
    .fetch_one(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let act_id: Uuid = act_row.try_get("id").map_err(|_| AppError::Internal)?;

    Ok(AddActResponse { act_id, warning })
}

/// `POST /v1/cabinet/consultations/:id/acts` — ajoute un acte CCAM (ou un
/// groupe d'actes composé, #4115) à la séance.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// - Vérifie que la séance existe et appartient au cabinet du token.
/// - Insère dans `consultation_act` (RLS garantit le scope tenant).
/// - Retourne `201`.
/// - Body invalide (ni/les deux de ccam_code+bundle_code, label vide en mode
///   ccam_code, amount_cents < 0, bundle_code inconnu ou sans ligne) → 422.
/// - Séance inexistante ou hors tenant → 404.
/// - Acte invasif à risque hémorragique + dossier médical mentionnant un
///   traitement anticoagulant → `409 clinical_risk_warning` bloquant (#4057,
///   table de correspondance v1 simple — voir constantes en tête de module).
pub async fn add_consultation_act(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<AddActBody>,
) -> Result<(StatusCode, Json<AddActApiResponse>), AppError> {
    let ccam_code = body
        .ccam_code
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let bundle_code = body
        .bundle_code
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    if ccam_code.is_some() == bundle_code.is_some() {
        // Ni l'un ni l'autre, ou les deux : ambigu.
        return Err(AppError::ValidationError);
    }
    if let Some(cents) = body.amount_cents {
        if cents < 0 {
            return Err(AppError::ValidationError);
        }
    }
    if ccam_code.is_some() && body.label.as_deref().is_none_or(|s| s.trim().is_empty()) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que la séance existe, appartient au cabinet et récupère appointment_id +
    // practitioner_id + statut pour les gardes métier.
    let session_row = sqlx::query(
        "SELECT cs.appointment_id, cs.practitioner_id, cs.status, a.patient_id \
         FROM consultation_session cs \
         JOIN appointment a ON a.id = cs.appointment_id \
         WHERE cs.id = $1 AND cs.cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let appointment_id: Uuid = session_row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = session_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let session_status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = session_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    // Seul le praticien qui a démarré la séance peut y ajouter des actes.
    // On compare le practitioner.user_id avec claims.sub.
    let prac_row = sqlx::query(
        "SELECT id FROM practitioner WHERE id = $1 AND user_id = $2 AND cabinet_id = $3",
    )
    .bind(practitioner_id)
    .bind(claims.sub)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if prac_row.is_none() {
        return Err(AppError::Forbidden);
    }

    // La séance doit être en cours pour accepter de nouveaux actes.
    if session_status != "in_progress" {
        return Err(AppError::InvalidStatus);
    }

    let is_optam = is_optam_practitioner(&mut tx, practitioner_id, claims.cabinet_id).await?;

    let response = if let Some(ccam_code) = ccam_code {
        let entered_amount = body.amount_cents.unwrap_or(0);
        let act = insert_one_act(
            &mut tx,
            claims.cabinet_id,
            appointment_id,
            patient_id,
            practitioner_id,
            ccam_code,
            body.label.as_deref().unwrap_or_default().trim(),
            body.tooth.as_deref(),
            entered_amount,
            Some(entered_amount),
            is_optam,
        )
        .await?;
        AddActApiResponse::Single(act)
    } else {
        let bundle_code = bundle_code.expect("XOR checked above");

        let bundle_exists = sqlx::query("SELECT 1 FROM ccam_act_bundle WHERE code = $1")
            .bind(bundle_code)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        if bundle_exists.is_none() {
            return Err(AppError::ValidationError);
        }

        let item_rows = sqlx::query(
            "SELECT c.code, c.label, c.tarif_cents, c.secteur1_cents, c.optam_cents, i.qty \
             FROM ccam_act_bundle_item i \
             JOIN ccam_act c ON c.code = i.ccam_code \
             WHERE i.bundle_code = $1",
        )
        .bind(bundle_code)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        if item_rows.is_empty() {
            return Err(AppError::ValidationError);
        }

        let mut acts = Vec::with_capacity(item_rows.len());
        for row in item_rows {
            let item_code: String = row.try_get("code").map_err(|_| AppError::Internal)?;
            let item_label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
            let tarif_cents: Option<i32> =
                row.try_get("tarif_cents").map_err(|_| AppError::Internal)?;
            let secteur1_cents: Option<i32> = row
                .try_get("secteur1_cents")
                .map_err(|_| AppError::Internal)?;
            let optam_cents: Option<i32> =
                row.try_get("optam_cents").map_err(|_| AppError::Internal)?;
            let qty: i32 = row.try_get("qty").map_err(|_| AppError::Internal)?;

            let applicable =
                select_applicable_tariff(is_optam, tarif_cents, secteur1_cents, optam_cents)
                    .unwrap_or(0);
            let final_amount = applicable * qty;

            let act = insert_one_act(
                &mut tx,
                claims.cabinet_id,
                appointment_id,
                patient_id,
                practitioner_id,
                &item_code,
                &item_label,
                body.tooth.as_deref(),
                final_amount,
                None,
                is_optam,
            )
            .await?;
            acts.push(act);
        }
        AddActApiResponse::Bundle { acts }
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %id,
        "consultation act(s) added"
    );

    Ok((StatusCode::CREATED, Json(response)))
}
