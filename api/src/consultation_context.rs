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

/// Sous-objet patient dans la réponse (bandeau patient de la vue fauteuil).
/// `birth_date` n'est JAMAIS exposé (minimisation) — seul l'âge calculé sort.
#[derive(Serialize)]
pub struct PatientSummary {
    pub id: Uuid,
    pub display_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub age_years: Option<i32>,
}

/// Sous-objet RDV dans la réponse (heure + motif affichés dans le bandeau).
#[derive(Serialize)]
pub struct AppointmentInfo {
    pub starts_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub motif: Option<String>,
}

/// Alerte médicale en AFFICHAGE PASSIF uniquement (pas d'aide à la décision —
/// périmètre non-dispositif-médical, docs/06 §E4.8). `kind` ∈
/// {`allergie`, `medico_legal`} ; le libellé est restitué tel que saisi.
#[derive(Serialize)]
pub struct MedicalAlertItem {
    pub kind: String,
    pub label: String,
}

/// Phase de plan de traitement en cours pour le patient (panneau
/// « Prochaine étape » de la vue fauteuil).
#[derive(Serialize)]
pub struct CurrentPhaseInfo {
    pub plan_id: Uuid,
    pub plan_title: String,
    pub phase_id: Uuid,
    pub phase_title: String,
    pub position: i32,
    pub phase_count: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub planned_sessions: Option<i32>,
    pub completed_sessions: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_phase_title: Option<String>,
}

/// Extrait de la note de la dernière séance terminée du patient
/// (« Dernière note · 14 avr. » dans le panneau contexte clinique).
#[derive(Serialize)]
pub struct LastNoteInfo {
    pub date: String,
    pub excerpt: String,
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
    /// `None` uniquement sur données incohérentes (RDV sans patient) —
    /// le front doit tolérer l'absence.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub patient: Option<PatientSummary>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub appointment: Option<AppointmentInfo>,
    /// Toujours sérialisé (liste vide si aucun facteur saisi au dossier).
    pub medical_alerts: Vec<MedicalAlertItem>,
    /// Antécédents en texte libre (`medical_record.history`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub medical_history: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current_phase: Option<CurrentPhaseInfo>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_note: Option<LastNoteInfo>,
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

    // Séance + display_name du praticien via provider (peut être NULL si provider absent).
    let session_row = sqlx::query(
        "SELECT cs.id, cs.appointment_id, cs.practitioner_id, cs.status, \
                cs.started_at, cs.completed_at, cs.note_ciphertext, cs.note_key_ref, \
                COALESCE(p.display_name, '') AS display_name \
         FROM consultation_session cs \
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

    // RLS strict E.2.16.c : le praticien appelant doit avoir eu au moins un
    // appointment avec le patient de cette séance (§14 — miroir de medical_record.rs).
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = (SELECT patient_id FROM appointment WHERE id = $1 AND cabinet_id = $2) \
           AND a.cabinet_id = $2 AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(appointment_id)
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

    // ── Enrichissements vue fauteuil (refonte consultation, lot 1) ───────────
    // Un seul aller-retour HTTP pour tout le contexte : patient + RDV,
    // alertes médicales passives, phase de plan courante, dernière note.

    // Patient + RDV. `age_years` calculé en SQL — `birth_date` ne sort jamais.
    let patient_row = sqlx::query(
        "SELECT pt.id AS patient_id, pt.first_name, pt.last_name, \
                CASE WHEN pt.birth_date IS NULL THEN NULL \
                     ELSE date_part('year', age(pt.birth_date))::int END AS age_years, \
                a.starts_at, a.motif \
         FROM appointment a \
         JOIN patient pt ON pt.id = a.patient_id AND pt.cabinet_id = a.cabinet_id \
         WHERE a.id = $1 AND a.cabinet_id = $2",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (patient, appointment, patient_id) = match patient_row {
        Some(row) => {
            let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
            let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
            let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
            let age_years: Option<i32> = row.try_get("age_years").unwrap_or(None);
            let starts_at: chrono::DateTime<chrono::Utc> =
                row.try_get("starts_at").map_err(|_| AppError::Internal)?;
            let motif: Option<String> = row.try_get("motif").unwrap_or(None);
            (
                Some(PatientSummary {
                    id: patient_id,
                    display_name: format!("{first_name} {last_name}").trim().to_string(),
                    age_years,
                }),
                Some(AppointmentInfo {
                    starts_at: starts_at.to_rfc3339(),
                    motif,
                }),
                Some(patient_id),
            )
        }
        None => (None, None, None),
    };

    // Alertes médicales + antécédents — même source déchiffrée que le moteur
    // d'alertes de `consultation_act_create.rs` (#4057). Affichage passif only.
    let (medical_alerts, medical_history) = match patient_id {
        Some(pid) => {
            let mr_row = sqlx::query(
                "SELECT data_ciphertext FROM medical_record \
                 WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
                 ORDER BY updated_at DESC LIMIT 1",
            )
            .bind(pid)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

            mr_row
                .and_then(|row| row.try_get::<Vec<u8>, _>("data_ciphertext").ok())
                .and_then(|ct| crate::medical_record::decrypt_stub(&ct))
                .map(|data| (build_medical_alerts(&data), extract_history(&data)))
                .unwrap_or((Vec::new(), None))
        }
        None => (Vec::new(), None),
    };

    // Phase courante : plan `in_progress` prioritaire sur `accepted`, phase
    // `in_progress` prioritaire sur la première non-`done` (ordre `position`).
    let current_phase = match patient_id {
        Some(pid) => {
            let row = sqlx::query(
                "SELECT tp.id AS plan_id, tp.title AS plan_title, \
                        ph.id AS phase_id, ph.title AS phase_title, ph.position, \
                        ph.planned_sessions, ph.completed_sessions, \
                        (SELECT count(*)::int FROM treatment_phase c WHERE c.plan_id = tp.id) AS phase_count, \
                        (SELECT n.title FROM treatment_phase n \
                          WHERE n.plan_id = tp.id AND n.position > ph.position \
                          ORDER BY n.position ASC LIMIT 1) AS next_phase_title \
                 FROM treatment_plan tp \
                 JOIN treatment_phase ph ON ph.plan_id = tp.id \
                 WHERE tp.patient_id = $1 AND tp.cabinet_id = $2 \
                   AND tp.deleted_at IS NULL \
                   AND tp.status IN ('accepted','in_progress') \
                   AND ph.status <> 'done' \
                 ORDER BY CASE WHEN tp.status = 'in_progress' THEN 0 ELSE 1 END, \
                          tp.created_at DESC, \
                          CASE WHEN ph.status = 'in_progress' THEN 0 ELSE 1 END, \
                          ph.position ASC \
                 LIMIT 1",
            )
            .bind(pid)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

            match row {
                Some(row) => Some(CurrentPhaseInfo {
                    plan_id: row.try_get("plan_id").map_err(|_| AppError::Internal)?,
                    plan_title: row.try_get("plan_title").map_err(|_| AppError::Internal)?,
                    phase_id: row.try_get("phase_id").map_err(|_| AppError::Internal)?,
                    phase_title: row.try_get("phase_title").map_err(|_| AppError::Internal)?,
                    position: row.try_get("position").map_err(|_| AppError::Internal)?,
                    phase_count: row.try_get("phase_count").map_err(|_| AppError::Internal)?,
                    planned_sessions: row.try_get("planned_sessions").unwrap_or(None),
                    completed_sessions: row
                        .try_get("completed_sessions")
                        .map_err(|_| AppError::Internal)?,
                    next_phase_title: row.try_get("next_phase_title").unwrap_or(None),
                }),
                None => None,
            }
        }
        None => None,
    };

    // Dernière note d'une séance terminée du patient (hors séance courante).
    let last_note = match patient_id {
        Some(pid) => {
            let row = sqlx::query(
                "SELECT cs2.completed_at, cs2.note_ciphertext \
                 FROM consultation_session cs2 \
                 JOIN appointment a2 ON a2.id = cs2.appointment_id \
                 WHERE a2.patient_id = $1 AND cs2.cabinet_id = $2 \
                   AND cs2.status = 'completed' AND cs2.id <> $3 \
                   AND cs2.note_ciphertext IS NOT NULL \
                 ORDER BY cs2.completed_at DESC NULLS LAST \
                 LIMIT 1",
            )
            .bind(pid)
            .bind(claims.cabinet_id)
            .bind(session_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

            row.and_then(|row| {
                let completed: Option<chrono::DateTime<chrono::Utc>> =
                    row.try_get("completed_at").unwrap_or(None);
                let ct: Option<Vec<u8>> = row.try_get("note_ciphertext").unwrap_or(None);
                let text = ct.as_deref().and_then(stub_decrypt_note)?;
                Some(LastNoteInfo {
                    date: completed.map(|t| t.to_rfc3339()).unwrap_or_default(),
                    excerpt: note_excerpt(&text),
                })
            })
        }
        None => None,
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

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
        patient,
        appointment,
        medical_alerts,
        medical_history,
        current_phase,
        last_note,
    }))
}

/// Construit les alertes passives du bandeau patient depuis le JSON
/// `medical_record` déchiffré (`{ allergies: [...], medico_legal: {...} }`).
/// Allergies : chaque entrée libre (chaîne ou objet `{label}`/`{name}`) devient
/// une alerte `kind = "allergie"`. Flags structurés `medico_legal` (#4103) :
/// libellés fixes, jamais déduits du texte libre.
fn build_medical_alerts(data: &serde_json::Value) -> Vec<MedicalAlertItem> {
    let mut alerts = Vec::new();

    if let Some(arr) = data["allergies"].as_array() {
        for entry in arr {
            let label = entry
                .as_str()
                .map(str::to_string)
                .or_else(|| entry["label"].as_str().map(str::to_string))
                .or_else(|| entry["name"].as_str().map(str::to_string));
            if let Some(label) = label {
                if !label.trim().is_empty() {
                    alerts.push(MedicalAlertItem {
                        kind: "allergie".into(),
                        label: label.trim().to_string(),
                    });
                }
            }
        }
    }

    const FLAGS: [(&str, &str); 4] = [
        ("anticoagulants", "Anticoagulants"),
        ("bisphosphonates", "Bisphosphonates"),
        ("risque_endocardite", "Risque d'endocardite"),
        ("ald", "ALD"),
    ];
    for (key, label) in FLAGS {
        if data["medico_legal"][key].as_bool().unwrap_or(false) {
            alerts.push(MedicalAlertItem {
                kind: "medico_legal".into(),
                label: label.into(),
            });
        }
    }

    alerts
}

/// Antécédents en texte libre (`medical_record.history`), `None` si vide.
fn extract_history(data: &serde_json::Value) -> Option<String> {
    data["history"]
        .as_str()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// Tronque une note à 200 caractères (limite en caractères, pas en octets —
/// une coupe au milieu d'un caractère UTF-8 paniquerait avec un slice).
fn note_excerpt(note: &str) -> String {
    const MAX_CHARS: usize = 200;
    let trimmed = note.trim();
    if trimmed.chars().count() <= MAX_CHARS {
        trimmed.to_string()
    } else {
        let cut: String = trimmed.chars().take(MAX_CHARS).collect();
        format!("{cut}…")
    }
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
