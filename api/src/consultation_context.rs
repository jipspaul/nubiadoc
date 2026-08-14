//! Handler `GET /v1/cabinet/consultations/:id` — extrait de `consultations.rs`
//! (refactor pur, aucun changement de comportement) : `consultations.rs`
//! dépassait le plafond absolu de 700 lignes (CLAUDE.md), et l'ajout prévu
//! du fix #4260 (statut `sent` sur le devis de clôture) l'aurait aggravé.
//! Ce fichier contient tout ce que `get_consultation_context` utilise en
//! propre (structs de réponse + le stub `stub_decrypt_note`, sans autre
//! appelant dans `consultations.rs`).

use axum::{
    extract::{Path, State},
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    medical_record::{decrypt_stub, MedicoLegalFlags},
    AppState,
};

/// Un acte CCAM réalisé pendant la séance.
#[derive(Serialize)]
pub struct ConsultationActItem {
    pub id: Uuid,
    pub ccam_code: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth: Option<String>,
    pub amount_cents: i32,
}

/// Sous-objet praticien dans la réponse.
#[derive(Serialize)]
pub struct PractitionerSummary {
    pub id: Uuid,
    pub display_name: String,
}

/// Alerte médicale passive listée dans l'encart « Alertes du dossier » de la
/// colonne contexte (#4936) — AFFICHAGE PASSIF uniquement (périmètre
/// non-dispositif-médical), aucun contrôle ici : le blocage
/// anticoagulants/acte invasif reste dans `consultation_act_create.rs` (#4057).
/// `kind` : `allergie` | `medico_legal`.
#[derive(Serialize)]
pub struct MedicalAlertItem {
    pub kind: String,
    pub label: String,
}

/// Réponse de `GET /v1/cabinet/consultations/:id`.
#[derive(Serialize)]
pub struct ConsultationContextResponse {
    pub id: Uuid,
    pub appointment_id: Uuid,
    pub status: String,
    pub started_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
    pub practitioner: PractitionerSummary,
    /// Note clinique déchiffrée. `None` si aucune note enregistrée.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    pub acts: Vec<ConsultationActItem>,
    /// Patient de la séance — sert au cloisonnement de l'historique
    /// « Dernières séances » (#4937, filtre `patient_id` sur `listSessions`).
    pub patient_id: Uuid,
    /// Alertes médicales du dossier patient (allergies + flags médico-légaux
    /// structurés, #4103). Tableau vide si le dossier n'a aucune alerte —
    /// jamais d'entrée inventée côté front (#4936).
    pub medical_alerts: Vec<MedicalAlertItem>,
}

/// `GET /v1/cabinet/consultations/:id` — contexte clinique d'une séance au fauteuil.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// Garde relation-de-soin E.2.16.c §14 (miroir `medical_record.rs`) : le praticien
/// appelant doit avoir eu au moins un `appointment` avec le patient de la séance,
/// sinon 403 — même s'il est dans le même cabinet.
/// Note clinique : déchiffrée via stub `STUB_ENC:` (AES-256-GCM/KMS à NUB-T3, ADR-009).
/// Séance inexistante ou hors tenant → 404.
pub async fn get_consultation_context(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<ConsultationContextResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Séance + display_name du praticien via provider (peut être NULL si provider absent)
    // + patient_id de l'appointment (#4937 — cloisonnement de l'historique patient).
    let session_row = sqlx::query(
        "SELECT cs.id, cs.appointment_id, cs.practitioner_id, cs.status, \
                cs.started_at, cs.completed_at, cs.note_ciphertext, cs.note_key_ref, \
                a.patient_id, \
                COALESCE(p.display_name, '') AS display_name \
         FROM consultation_session cs \
         JOIN appointment a ON a.id = cs.appointment_id \
         LEFT JOIN provider p ON p.practitioner_id = cs.practitioner_id \
                              AND p.cabinet_id = cs.cabinet_id \
         WHERE cs.id = $1 AND cs.cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let session_id: Uuid = session_row.try_get("id").map_err(|_| AppError::Internal)?;
    let appointment_id: Uuid = session_row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = session_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = session_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    // RLS strict E.2.16.c : le praticien appelant doit avoir eu au moins un
    // appointment avec le patient de cette séance (§14 — miroir de medical_record.rs).
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 \
           AND a.cabinet_id = $2 AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    let started_at: chrono::DateTime<chrono::Utc> = session_row
        .try_get("started_at")
        .map_err(|_| AppError::Internal)?;
    let completed_at: Option<chrono::DateTime<chrono::Utc>> = session_row
        .try_get("completed_at")
        .map_err(|_| AppError::Internal)?;
    let note_ciphertext: Option<Vec<u8>> = session_row
        .try_get("note_ciphertext")
        .map_err(|_| AppError::Internal)?;
    let display_name: String = session_row
        .try_get("display_name")
        .map_err(|_| AppError::Internal)?;

    // Déchiffre `note_ciphertext` via stub (KMS/AES-256-GCM à NUB-T3, ADR-009) —
    // voir `clinical.rs::add_patient_note` pour le même stub sur `clinical_note`.
    let note: Option<String> = note_ciphertext.as_deref().and_then(stub_decrypt_note);

    // Actes CCAM de la séance.
    let act_rows = sqlx::query(
        "SELECT id, ccam_code, label, tooth, amount_cents \
         FROM consultation_act \
         WHERE appointment_id = $1 AND cabinet_id = $2 \
         ORDER BY created_at ASC",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Alertes du dossier (#4936) — dernier dossier médical du patient de la
    // séance (même requête que `consultation_act_create.rs::add_consultation_act`
    // pour la garde anticoagulants). `patient_id` déjà récupéré via la jointure
    // `appointment` ci-dessus (#4937).
    let record_row = sqlx::query(
        "SELECT data_ciphertext FROM medical_record \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY updated_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut medical_alerts: Vec<MedicalAlertItem> = Vec::new();
    if let Some(row) = record_row {
        let ciphertext: Vec<u8> = row
            .try_get("data_ciphertext")
            .map_err(|_| AppError::Internal)?;
        if let Some(data) = decrypt_stub(&ciphertext) {
            for entry in data["allergies"].as_array().into_iter().flatten() {
                if let Some(label) = allergy_label(entry) {
                    medical_alerts.push(MedicalAlertItem {
                        kind: "allergie".to_string(),
                        label,
                    });
                }
            }
            let medico_legal: MedicoLegalFlags = data
                .get("medico_legal")
                .and_then(|v| serde_json::from_value(v.clone()).ok())
                .unwrap_or_default();
            medical_alerts.extend(medico_legal_alerts(&medico_legal));
        }
    }

    let mut acts: Vec<ConsultationActItem> = Vec::with_capacity(act_rows.len());
    for row in act_rows {
        let act_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let ccam_code: String = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
        let amount_cents: i32 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        acts.push(ConsultationActItem {
            id: act_id,
            ccam_code,
            label,
            tooth,
            amount_cents,
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %session_id,
        "consultation context queried"
    );

    Ok(Json(ConsultationContextResponse {
        id: session_id,
        appointment_id,
        status,
        started_at: started_at.to_rfc3339(),
        completed_at: completed_at.map(|t| t.to_rfc3339()),
        practitioner: PractitionerSummary {
            id: practitioner_id,
            display_name,
        },
        note,
        acts,
        patient_id,
        medical_alerts,
    }))
}

/// Extrait un libellé d'alerte affichable depuis une entrée `allergies[]`
/// (`jsonb` libre, même tolérance que `medical_record.rs` / le front
/// `medical_record_dto.dart::_entryToDisplayString` : chaîne brute ou objet
/// `{"name"|"label": "..."}`). `None` si l'entrée est vide/illisible — jamais
/// d'alerte inventée.
fn allergy_label(entry: &serde_json::Value) -> Option<String> {
    let label = if let Some(s) = entry.as_str() {
        s
    } else {
        entry
            .get("name")
            .or_else(|| entry.get("label"))
            .and_then(|v| v.as_str())?
    };
    let label = label.trim();
    if label.is_empty() {
        None
    } else {
        Some(label.to_string())
    }
}

/// Traduit les flags médico-légaux structurés (#4103) en alertes affichables.
/// Seuls les flags à `true` produisent une entrée.
fn medico_legal_alerts(flags: &MedicoLegalFlags) -> Vec<MedicalAlertItem> {
    let mut alerts = Vec::new();
    if flags.anticoagulants {
        alerts.push(MedicalAlertItem {
            kind: "medico_legal".to_string(),
            label: "Anticoagulant (AVK)".to_string(),
        });
    }
    if flags.bisphosphonates {
        alerts.push(MedicalAlertItem {
            kind: "medico_legal".to_string(),
            label: "Bisphosphonates".to_string(),
        });
    }
    if flags.risque_endocardite {
        alerts.push(MedicalAlertItem {
            kind: "medico_legal".to_string(),
            label: "Risque d'endocardite".to_string(),
        });
    }
    if flags.ald {
        alerts.push(MedicalAlertItem {
            kind: "medico_legal".to_string(),
            label: "ALD".to_string(),
        });
    }
    alerts
}

/// Déchiffre une note de séance : préfixe `"STUB_ENC:"` puis XOR 0xFF octet
/// par octet. Même stub que `clinical.rs::add_patient_note` (KMS/AES-256-GCM
/// à NUB-T3, ADR-009). `None` si préfixe absent (ex. legacy/scaffold).
fn stub_decrypt_note(ciphertext: &[u8]) -> Option<String> {
    let prefix = b"STUB_ENC:";
    let payload = ciphertext.strip_prefix(prefix.as_ref())?;
    let plain: Vec<u8> = payload.iter().map(|b| b ^ 0xFF).collect();
    String::from_utf8(plain).ok()
}
