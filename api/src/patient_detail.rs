//! Handler `GET /v1/cabinet/patients/:id` — extrait de `clinical.rs`
//! (refactor pur, aucun changement de comportement) : `clinical.rs` dépassait
//! le plafond absolu de 700 lignes (CLAUDE.md), et l'ajout prévu de
//! `no_show_count` (#4090) aurait aggravé le dépassement. Ce fichier
//! contient tout ce que `get_cabinet_patient` utilise en propre (structs de
//! réponse + le stub `stub_decrypt_medical_record`, sans autre appelant dans
//! `clinical.rs`) ; `stub_decrypt` reste partagé (`clinical.rs`, aussi utilisé
//! par `list_patient_notes`), référencé ici via `crate::clinical::stub_decrypt`.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::Serialize;
use serde_json::Value;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    patient_satisfaction::{aggregate_patient_satisfaction, PatientSatisfactionSummary},
    AppState,
};

/// Partie administrative de la fiche patient (visible par tous les rôles pro).
#[derive(Serialize)]
pub struct PatientAdminSection {
    pub id: Uuid,
    pub first_name: String,
    pub last_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub birth_date: Option<String>,
    pub contact: Value,
    pub mutuelle: Value,
    /// Solde restant dû (US-4.6.2, #4044), en centimes — devis signés du
    /// patient moins paiements déjà engagés (`pending`/`paid`, jamais
    /// `failed`/`refunded`), même formule que `remaining_due_cents`
    /// (`create_payment_intent`, `billing.rs`) mais agrégée au patient
    /// (tous ses devis signés) plutôt qu'à un seul devis.
    pub balance_due_cents: i64,
    /// Note moyenne + dernier avis publié laissé par ce patient envers un
    /// praticien de CE cabinet (#4161) — `null` si aucun avis. Jamais les
    /// avis laissés dans un autre cabinet (cloisonnement tenant).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub satisfaction: Option<PatientSatisfactionSummary>,
    pub created_at: String,
}

/// Réponse complète praticien (admin + données cliniques).
#[derive(Serialize)]
pub struct PatientDetailPractitioner {
    #[serde(flatten)]
    pub admin: PatientAdminSection,
    /// Antécédents / allergies / traitements — ciphertext décodé stub en dev.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub medical_record: Option<MedicalRecordSection>,
    /// Dernières notes cliniques (max 10, déchiffrées stub).
    pub notes: Vec<ClinicalNoteSummary>,
}

/// Réponse réduite secrétaire : sections cliniques absentes (R.4127-72).
#[derive(Serialize)]
pub struct PatientDetailSecretary {
    #[serde(flatten)]
    pub admin: PatientAdminSection,
}

#[derive(Serialize)]
pub struct MedicalRecordSection {
    pub id: Uuid,
    /// Contenu déchiffré stub (`"STUB_DEC:<base64>"` en dev — AES-256-GCM KMS à NUB-T3).
    pub data: String,
    pub updated_at: String,
}

#[derive(Serialize)]
pub struct ClinicalNoteSummary {
    pub id: Uuid,
    pub note_kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth: Option<String>,
    /// Contenu déchiffré stub en dev.
    pub text: String,
    pub created_at: String,
}

/// Réponse unifiée : `medical_record` et `notes` présents ↔ rôle praticien.
#[derive(Serialize)]
#[serde(untagged)]
pub enum PatientDetailResponse {
    Practitioner(PatientDetailPractitioner),
    Secretary(PatientDetailSecretary),
}

/// Inverse du stub chiffrement `medical_record` (voir `medical_record.rs::encrypt_stub`) :
/// pas de XOR, seulement le strip du préfixe `STUB_ENC:` — la valeur chiffrée est déjà
/// le JSON en clair préfixé.
fn stub_decrypt_medical_record(ciphertext: &[u8]) -> Option<String> {
    let prefix = b"STUB_ENC:";
    let payload = ciphertext.strip_prefix(prefix.as_ref())?;
    String::from_utf8(payload.to_vec()).ok()
}

/// `GET /v1/cabinet/patients/:id` — fiche patient, vue selon rôle.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, jamais du path (invariant tenancy).
/// RLS via `app.current_cabinet_id`. Patient hors cabinet → 404.
///
/// - `secretary` : retourne uniquement la partie administrative (R.4127-72, §07 §4.1).
///   Pas de 403 : les champs cliniques sont *omis*, pas interdits.
/// - `practitioner` / `admin` : retourne la fiche complète + audite `read_record`.
///   Si le praticien n'a aucun `appointment` avec ce patient (pas de relation de
///   soin, §14), dégrade vers la partie administrative (200) au lieu d'un 403 —
///   cohérence avec `list_cabinet_patients`, qui ne filtre pas sur cette relation
///   pour le praticien (#3767).
pub async fn get_cabinet_patient(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<PatientDetailResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, first_name, last_name, birth_date, contact, mutuelle, created_at, \
                patient_account_id \
         FROM patient \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
    let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
    let birth_date: Option<chrono::NaiveDate> =
        row.try_get("birth_date").map_err(|_| AppError::Internal)?;
    let contact: Value = row.try_get("contact").map_err(|_| AppError::Internal)?;
    let mut mutuelle: Value = row.try_get("mutuelle").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let patient_account_id: Option<Uuid> = row
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;

    // `patient.mutuelle` n'est jamais écrite par le flux normal (cf. issue #3485) : pour
    // un patient ayant un compte plateforme lié, la couverture réelle vit dans
    // `patient_coverage` (scope patient, RLS fail-closed sur `app.patient_account_id`).
    // On impersonifie temporairement ce GUC (même pattern que `create_cabinet_patient`
    // pour lire `patient_account`) afin de la lire et de la refléter côté cabinet.
    if let Some(account_id) = patient_account_id {
        sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
            .bind(account_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let coverage_row = sqlx::query(
            "SELECT amc, numero_adherent, plateforme, tiers_payant \
             FROM patient_coverage \
             WHERE patient_account_id = $1",
        )
        .bind(account_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if let Some(cov) = coverage_row {
            let amc: Option<String> = cov.try_get("amc").map_err(|_| AppError::Internal)?;
            let numero_adherent: Option<String> = cov
                .try_get("numero_adherent")
                .map_err(|_| AppError::Internal)?;
            let plateforme: Option<String> =
                cov.try_get("plateforme").map_err(|_| AppError::Internal)?;
            let tiers_payant: bool = cov
                .try_get("tiers_payant")
                .map_err(|_| AppError::Internal)?;
            mutuelle = serde_json::json!({
                "amc": amc,
                "numero_adherent": numero_adherent,
                "plateforme": plateforme,
                "tiers_payant": tiers_payant,
            });
        }

        // Restaure le contexte cabinet pour le reste de la transaction (RLS patient).
        sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
            .bind("")
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    }

    // Solde restant dû (US-4.6.2, #4044) : somme des devis SIGNÉS (seuls les
    // devis signés engagent le patient — draft/sent/refused/expired ne sont
    // pas une dette) moins somme des paiements pending/paid (jamais
    // failed/refunded, qui n'engagent aucune somme — même exclusion que
    // `create_payment_intent`, billing.rs). RLS tenant_isolation déjà
    // satisfaite par le GUC app.current_cabinet_id positionné plus haut.
    let balance_row = sqlx::query(
        "SELECT (( \
           COALESCE((SELECT SUM(total_amount) FROM quote \
                     WHERE patient_id = $1 AND cabinet_id = $2 \
                       AND status = 'signed' AND deleted_at IS NULL), 0) \
           - \
           COALESCE((SELECT SUM(amount) FROM payment \
                     WHERE patient_id = $1 AND cabinet_id = $2 \
                       AND status IN ('pending', 'paid')), 0) \
         ) * 100)::bigint AS balance_due_cents",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let balance_due_cents: i64 = balance_row
        .try_get("balance_due_cents")
        .map_err(|_| AppError::Internal)?;

    // Satisfaction (#4161) : nécessite un compte plateforme lié (les avis
    // sont rattachés à patient_account, pas à patient) — None sinon.
    let satisfaction = match patient_account_id {
        Some(account_id) => {
            aggregate_patient_satisfaction(&mut tx, account_id, claims.cabinet_id).await?
        }
        None => None,
    };

    let admin = PatientAdminSection {
        id,
        first_name,
        last_name,
        birth_date: birth_date.map(|d| d.to_string()),
        contact,
        mutuelle,
        balance_due_cents,
        satisfaction,
        created_at: created_at.to_rfc3339(),
    };

    // Secrétaire : retourne uniquement la partie administrative (R.4127-72).
    if claims.role == "secretary" {
        // Même garde de scope secrétariat que list_cabinet_patients (R10) :
        // sans elle, le détail exposait le dossier admin/mutuelle d'un patient
        // que la LISTE de cette même secrétaire masque déjà — contournement
        // trivial par accès direct à l'URL (#3821).
        let in_scope = match claims.secretariat_id {
            Some(secretariat_id) => sqlx::query(
                "SELECT 1 FROM appointment a \
                 JOIN provider pr ON pr.practitioner_id = a.practitioner_id \
                 JOIN provider_secretariat ps ON ps.provider_id = pr.id \
                 WHERE a.patient_id = $1 \
                   AND a.deleted_at IS NULL \
                   AND a.status <> 'cancelled' \
                   AND ps.secretariat_id = $2 \
                   AND ps.active = true",
            )
            .bind(patient_id)
            .bind(secretariat_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .is_some(),
            // Secrétaire sans secrétariat actif : aucun patient visible (comme la liste).
            None => false,
        };
        if !in_scope {
            return Err(AppError::NotFound);
        }

        tx.commit().await.map_err(|_| AppError::Internal)?;
        tracing::info!(
            cabinet_id = %claims.cabinet_id,
            user_id = %claims.sub,
            patient_id = %patient_id,
            role = "secretary",
            "patient detail fetched (secretary — clinical sections omitted)"
        );
        return Ok(Json(PatientDetailResponse::Secretary(
            PatientDetailSecretary { admin },
        )));
    }

    // Praticien / admin : charge les données cliniques.

    // RLS strict E.2.16.c : le praticien doit avoir eu au moins un appointment
    // avec ce patient dans ce cabinet (§14 — accès journal clinique), même
    // garde que list_patient_notes / list_patient_documents.
    if claims.role == "practitioner" {
        let has_appointment = sqlx::query(
            "SELECT 1 FROM appointment a \
             JOIN practitioner p ON p.id = a.practitioner_id \
             WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
               AND p.user_id = $3 AND a.deleted_at IS NULL",
        )
        .bind(patient_id)
        .bind(claims.cabinet_id)
        .bind(claims.sub)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if has_appointment.is_none() {
            // Pas de relation de soin avec ce patient : dégrade vers la section
            // administrative (même traitement que le secrétaire) au lieu d'un 403 sec,
            // pour rester cohérent avec `list_cabinet_patients` qui n'applique pas
            // cette garde pour le praticien et liste donc aussi ces patients (#3767).
            tx.commit().await.map_err(|_| AppError::Internal)?;
            tracing::info!(
                cabinet_id = %claims.cabinet_id,
                user_id = %claims.sub,
                patient_id = %patient_id,
                role = "practitioner",
                "patient detail fetched (practitioner without care relationship — clinical sections omitted)"
            );
            return Ok(Json(PatientDetailResponse::Secretary(
                PatientDetailSecretary { admin },
            )));
        }
    }

    // medical_record (une seule ligne par patient, si elle existe).
    let mr_row = sqlx::query(
        "SELECT id, data_ciphertext, updated_at \
         FROM medical_record \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY updated_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let medical_record = if let Some(mr) = mr_row {
        let mr_id: Uuid = mr.try_get("id").map_err(|_| AppError::Internal)?;
        let ciphertext: Option<Vec<u8>> = mr
            .try_get("data_ciphertext")
            .map_err(|_| AppError::Internal)?;
        let updated_at: chrono::DateTime<chrono::Utc> =
            mr.try_get("updated_at").map_err(|_| AppError::Internal)?;
        // Stub déchiffrement — AES-256-GCM KMS à NUB-T3 (ADR-009).
        let data = ciphertext
            .and_then(|b| stub_decrypt_medical_record(&b))
            .unwrap_or_default();
        Some(MedicalRecordSection {
            id: mr_id,
            data,
            updated_at: updated_at.to_rfc3339(),
        })
    } else {
        None
    };

    // Notes cliniques — 10 plus récentes, déchiffrées stub.
    let note_rows = sqlx::query(
        "SELECT id, note_kind, tooth, content_ciphertext, created_at \
         FROM clinical_note \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY created_at DESC LIMIT 10",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut notes: Vec<ClinicalNoteSummary> = Vec::with_capacity(note_rows.len());
    for nr in note_rows {
        let nid: Uuid = nr.try_get("id").map_err(|_| AppError::Internal)?;
        let note_kind: String = nr.try_get("note_kind").map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = nr.try_get("tooth").map_err(|_| AppError::Internal)?;
        let ciphertext: Vec<u8> = nr
            .try_get("content_ciphertext")
            .map_err(|_| AppError::Internal)?;
        let note_created_at: chrono::DateTime<chrono::Utc> =
            nr.try_get("created_at").map_err(|_| AppError::Internal)?;
        // Stub déchiffrement.
        let text = crate::clinical::stub_decrypt(&ciphertext).unwrap_or_default();
        notes.push(ClinicalNoteSummary {
            id: nid,
            note_kind,
            tooth,
            text,
            created_at: note_created_at.to_rfc3339(),
        });
    }

    // Audit — praticien/admin accède au dossier clinique.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'read_record', 'patient', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        role = %claims.role,
        "patient detail fetched (practitioner — full record)"
    );

    Ok(Json(PatientDetailResponse::Practitioner(
        PatientDetailPractitioner {
            admin,
            medical_record,
            notes,
        },
    )))
}
