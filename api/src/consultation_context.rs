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
    /// Horodatage d'ajout de l'acte (#4950 — heure `HH:MM` affichée sur la
    /// ligne d'acte). Toujours renseigné (`consultation_act.created_at` est
    /// `NOT NULL DEFAULT now()`).
    pub created_at: String,
    /// Traçabilité stérilisation (#4951) : `true` si une pochette
    /// stérilisée a été scannée pour cet acte (`sterilized_pouch`, #4137).
    pub sterilized: bool,
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
///
/// `severity` (#6917) : sévérité déclarée sur l'entrée `allergies[]` du
/// dossier (`{"substance": …, "severity": "high"}`), transmise telle quelle
/// (normalisée en minuscules) — omise du JSON quand l'entrée n'en porte pas.
/// Ajout additif au contrat : les clients qui ne lisent que `kind`/`label`
/// ne sont pas impactés.
#[derive(Serialize, Debug, Clone, PartialEq, Eq)]
pub struct MedicalAlertItem {
    pub kind: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub severity: Option<String>,
}

/// Résumé du plan de traitement actif du patient, pour l'encart « Plan en
/// cours » de la colonne contexte gauche (#4938). `current_phase` compte les
/// phases `done` + 1 (bornée à `total_phases`) : phase en cours = première
/// phase non terminée. `total_cost_cents` = somme des `quote_item` liés aux
/// phases du plan.
#[derive(Serialize)]
pub struct ActivePlanItem {
    pub id: Uuid,
    pub title: String,
    pub current_phase: i64,
    pub total_phases: i64,
    pub total_cost_cents: i64,
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
    /// Nom affichable du patient (#4945 — barre d'identité patient).
    pub patient_name: String,
    /// Date de naissance du patient, `YYYY-MM-DD` (#4945). `None` si absente
    /// du dossier patient.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub patient_birth_date: Option<String>,
    /// Alertes médicales du dossier patient (allergies + flags médico-légaux
    /// structurés, #4103). Tableau vide si le dossier n'a aucune alerte —
    /// jamais d'entrée inventée côté front (#4936).
    pub medical_alerts: Vec<MedicalAlertItem>,
    /// Plan de traitement actif du patient (statut `in_progress`, le plus
    /// récent, au moins une phase) — encart « Plan en cours » (#4938).
    /// `None` si aucun plan actif — jamais de plan inventé.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active_plan: Option<ActivePlanItem>,
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
    // + patient_id/nom/date de naissance de l'appointment (#4937 — cloisonnement
    // de l'historique patient ; #4945 — barre d'identité patient).
    let session_row = sqlx::query(
        "SELECT cs.id, cs.appointment_id, cs.practitioner_id, cs.status, \
                cs.started_at, cs.completed_at, cs.note_ciphertext, cs.note_key_ref, \
                a.patient_id, \
                COALESCE(pat.first_name || ' ' || pat.last_name, '') AS patient_name, \
                pat.birth_date, \
                COALESCE(p.display_name, '') AS display_name \
         FROM consultation_session cs \
         JOIN appointment a ON a.id = cs.appointment_id \
         LEFT JOIN patient pat ON pat.id = a.patient_id \
                               AND pat.cabinet_id = cs.cabinet_id \
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
    let patient_name: String = session_row
        .try_get("patient_name")
        .map_err(|_| AppError::Internal)?;
    let patient_birth_date: Option<chrono::NaiveDate> = session_row
        .try_get("birth_date")
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

    // Actes CCAM de la séance + statut de traçabilité stérilisation (#4951) :
    // un acte est « vérifié » soit qu'une pochette stérilisée lui a été
    // rattachée directement par un scan (`sterilized_pouch.consultation_act_id`,
    // #4137), soit qu'une pochette a été ouverte sur la séance elle-même
    // avant la saisie des actes (`sterilized_pouch.consultation_id`,
    // migration 0269, #7181/#7244 — sinon un sachet scanné par cette
    // nouvelle voie laissait `sterilized: false` sur tous les actes de la
    // séance, exactement le cas d'usage que 0269 dit vouloir couvrir).
    let act_rows = sqlx::query(
        "SELECT ca.id, ca.ccam_code, ca.label, ca.tooth, ca.amount_cents, ca.created_at, \
                EXISTS ( \
                    SELECT 1 FROM sterilized_pouch sp \
                    LEFT JOIN consultation_session cs \
                        ON cs.id = sp.consultation_id AND cs.cabinet_id = sp.cabinet_id \
                    WHERE sp.cabinet_id = ca.cabinet_id \
                      AND (sp.consultation_act_id = ca.id OR cs.appointment_id = ca.appointment_id) \
                ) AS sterilized \
         FROM consultation_act ca \
         WHERE ca.appointment_id = $1 AND ca.cabinet_id = $2 \
         ORDER BY ca.created_at ASC",
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

    // Plan de traitement actif (#4938) — plan `in_progress` le plus récent du
    // patient, avec ses phases et le coût total (quote_item liés).
    let active_plan_row = sqlx::query(
        "SELECT id, title FROM treatment_plan \
         WHERE patient_id = $1 AND cabinet_id = $2 AND status = 'in_progress' \
           AND deleted_at IS NULL \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut active_plan: Option<ActivePlanItem> = None;
    if let Some(plan_row) = active_plan_row {
        let plan_id: Uuid = plan_row.try_get("id").map_err(|_| AppError::Internal)?;
        let title: String = plan_row.try_get("title").map_err(|_| AppError::Internal)?;

        let phase_status_rows = sqlx::query(
            "SELECT status FROM treatment_phase WHERE plan_id = $1 ORDER BY position ASC",
        )
        .bind(plan_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let total_phases = phase_status_rows.len() as i64;
        if total_phases > 0 {
            let done_count = phase_status_rows
                .iter()
                .take_while(|row| {
                    row.try_get::<String, _>("status").ok().as_deref() == Some("done")
                })
                .count() as i64;
            let current_phase = (done_count + 1).min(total_phases);

            let total_cost_cents: i64 = sqlx::query_scalar(
                "SELECT COALESCE(SUM(qi.unit_amount * 100), 0)::bigint \
                 FROM quote_item qi \
                 JOIN treatment_phase tph ON tph.id = qi.phase_id \
                 WHERE tph.plan_id = $1",
            )
            .bind(plan_id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

            active_plan = Some(ActivePlanItem {
                id: plan_id,
                title,
                current_phase,
                total_phases,
                total_cost_cents,
            });
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut medical_alerts: Vec<MedicalAlertItem> = Vec::new();
    if let Some(row) = record_row {
        let ciphertext: Vec<u8> = row
            .try_get("data_ciphertext")
            .map_err(|_| AppError::Internal)?;
        if let Some(data) = decrypt_stub(&ciphertext) {
            medical_alerts = record_medical_alerts(&data);
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
        let act_created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        let sterilized: bool = row.try_get("sterilized").map_err(|_| AppError::Internal)?;
        acts.push(ConsultationActItem {
            id: act_id,
            ccam_code,
            label,
            tooth,
            amount_cents,
            created_at: act_created_at.to_rfc3339(),
            sterilized,
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
        patient_name,
        patient_birth_date: patient_birth_date.map(|d| d.to_string()),
        medical_alerts,
        active_plan,
    }))
}

/// Alertes affichables d'un dossier médical déchiffré (`{"allergies": [...],
/// "medico_legal": {...}}`) : une entrée `kind = "allergie"` par allergie
/// lisible (sévérité `high` en tête, ordre du dossier sinon), puis les flags
/// médico-légaux à `true`. Tableau vide si rien — jamais d'alerte inventée.
///
/// Point unique de calcul (#6917) partagé par `GET /v1/cabinet/consultations/:id`
/// et `GET`/`PATCH /v1/cabinet/patients/:id/medical-record` : les deux
/// en-têtes cliniques (fauteuil et fiche patient) affichent strictement les
/// mêmes pastilles.
pub(crate) fn record_medical_alerts(data: &serde_json::Value) -> Vec<MedicalAlertItem> {
    let mut alerts: Vec<MedicalAlertItem> = data["allergies"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(allergy_alert)
        .collect();
    // Tri stable : une allergie `high` avant toute autre, sans réordonner le
    // reste (l'ordre de saisie reste lisible pour le praticien).
    alerts.sort_by_key(|a| severity_rank(a.severity.as_deref()));
    let medico_legal: MedicoLegalFlags = data
        .get("medico_legal")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();
    alerts.extend(medico_legal_alerts(&medico_legal));
    alerts
}

/// Rang d'affichage d'une sévérité : `high` (0) < `medium`/`moderate` (1)
/// < `low` (2) < inconnue/absente (3).
fn severity_rank(severity: Option<&str>) -> u8 {
    match severity {
        Some("high" | "severe" | "critical") => 0,
        Some("medium" | "moderate") => 1,
        Some("low" | "mild") => 2,
        _ => 3,
    }
}

/// Convertit une entrée `allergies[]` (`jsonb` libre) en alerte affichable.
/// Toutes les formes réellement écrites en base sont acceptées (#6917) :
/// - chaîne nue `"Pénicilline"` ;
/// - objet structuré `{"substance": "…", "severity": "high"}` ;
/// - objet importé du questionnaire patient `{"text": "…", "source":
///   "questionnaire_patient"}` (`medical_questionnaire.rs`) ;
/// - objets `{"name": "…"}` / `{"label": "…"}` (formes historiques, même
///   tolérance que le front `medical_record_dto.dart::_entryToDisplayString`).
///
/// `None` si aucun libellé non vide n'est lisible — jamais d'alerte inventée.
///
/// `pub(crate)` — réutilisé par `medical_record.rs` (#4974) pour exposer les
/// mêmes pastilles d'alerte dans l'en-tête de la fiche patient qu'au fauteuil.
pub(crate) fn allergy_alert(entry: &serde_json::Value) -> Option<MedicalAlertItem> {
    let label = allergy_label(entry)?;
    let severity = entry
        .get("severity")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_lowercase())
        .filter(|s| !s.is_empty());
    Some(MedicalAlertItem {
        kind: "allergie".to_string(),
        label,
        severity,
    })
}

/// Libellé d'une entrée `allergies[]` — cf. [allergy_alert] pour les formes
/// acceptées. Première clé non vide parmi `substance`, `text`, `name`, `label`.
pub(crate) fn allergy_label(entry: &serde_json::Value) -> Option<String> {
    const LABEL_KEYS: [&str; 4] = ["substance", "text", "name", "label"];
    let label = if let Some(s) = entry.as_str() {
        s.trim()
    } else {
        LABEL_KEYS
            .iter()
            .filter_map(|k| entry.get(k).and_then(|v| v.as_str()))
            .map(str::trim)
            .find(|s| !s.is_empty())?
    };
    if label.is_empty() {
        None
    } else {
        Some(label.to_string())
    }
}

/// Traduit les flags médico-légaux structurés (#4103) en alertes affichables.
/// Seuls les flags à `true` produisent une entrée.
///
/// `pub(crate)` — réutilisé par `medical_record.rs` (#4974), cf. [allergy_label].
pub(crate) fn medico_legal_alerts(flags: &MedicoLegalFlags) -> Vec<MedicalAlertItem> {
    let mut alerts = Vec::new();
    if flags.anticoagulants {
        alerts.push(MedicalAlertItem {
            kind: "medico_legal".to_string(),
            label: "Anticoagulant (AVK)".to_string(),
            severity: None,
        });
    }
    if flags.bisphosphonates {
        alerts.push(MedicalAlertItem {
            kind: "medico_legal".to_string(),
            label: "Bisphosphonates".to_string(),
            severity: None,
        });
    }
    if flags.risque_endocardite {
        alerts.push(MedicalAlertItem {
            kind: "medico_legal".to_string(),
            label: "Risque d'endocardite".to_string(),
            severity: None,
        });
    }
    if flags.ald {
        alerts.push(MedicalAlertItem {
            kind: "medico_legal".to_string(),
            label: "ALD".to_string(),
            severity: None,
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn allergy_label_accepts_every_stored_shape() {
        assert_eq!(
            allergy_label(&json!("Pénicilline")).as_deref(),
            Some("Pénicilline")
        );
        assert_eq!(
            allergy_label(&json!({"severity": "high", "substance": "pénicilline"})).as_deref(),
            Some("pénicilline")
        );
        assert_eq!(
            allergy_label(&json!({"source": "questionnaire_patient", "text": " latex "}))
                .as_deref(),
            Some("latex")
        );
        assert_eq!(
            allergy_label(&json!({"name": "Iode"})).as_deref(),
            Some("Iode")
        );
        assert_eq!(
            allergy_label(&json!({"label": "Aspirine"})).as_deref(),
            Some("Aspirine")
        );
        // Première clé non vide : `substance` vide → retombe sur `text`.
        assert_eq!(
            allergy_label(&json!({"substance": "", "text": "nickel"})).as_deref(),
            Some("nickel")
        );
    }

    #[test]
    fn allergy_label_never_invents_an_alert() {
        assert_eq!(allergy_label(&json!("")), None);
        assert_eq!(allergy_label(&json!("   ")), None);
        assert_eq!(allergy_label(&json!({"text": ""})), None);
        assert_eq!(allergy_label(&json!({"severity": "high"})), None);
        assert_eq!(allergy_label(&json!({"text": 42})), None);
        assert_eq!(allergy_label(&json!(null)), None);
        assert_eq!(allergy_label(&json!(["Pénicilline"])), None);
    }

    #[test]
    fn allergy_alert_carries_normalised_severity() {
        let alert = allergy_alert(&json!({"substance": "pénicilline", "severity": " High "}))
            .expect("alerte attendue");
        assert_eq!(alert.kind, "allergie");
        assert_eq!(alert.label, "pénicilline");
        assert_eq!(alert.severity.as_deref(), Some("high"));

        let alert = allergy_alert(&json!({"text": "latex", "severity": ""})).expect("alerte");
        assert_eq!(alert.severity, None);
        let alert = allergy_alert(&json!("Nickel")).expect("alerte");
        assert_eq!(alert.severity, None);
    }

    #[test]
    fn record_medical_alerts_lists_every_allergy_high_first_then_flags() {
        let data = json!({
            "allergies": [
                { "source": "questionnaire_patient", "text": "latex" },
                "Nickel",
                { "severity": "high", "substance": "pénicilline" },
                { "text": "" }
            ],
            "treatments": [],
            "history": null,
            "medico_legal": { "ald": true, "anticoagulants": true }
        });
        let alerts = record_medical_alerts(&data);
        let view: Vec<(&str, &str, Option<&str>)> = alerts
            .iter()
            .map(|a| (a.kind.as_str(), a.label.as_str(), a.severity.as_deref()))
            .collect();
        assert_eq!(
            view,
            vec![
                ("allergie", "pénicilline", Some("high")),
                ("allergie", "latex", None),
                ("allergie", "Nickel", None),
                ("medico_legal", "Anticoagulant (AVK)", None),
                ("medico_legal", "ALD", None),
            ]
        );
    }

    #[test]
    fn record_medical_alerts_is_empty_without_allergy_nor_flag() {
        assert!(record_medical_alerts(&json!({"allergies": [], "treatments": []})).is_empty());
        assert!(record_medical_alerts(&json!({})).is_empty());
        assert!(record_medical_alerts(&json!({"allergies": "pas un tableau"})).is_empty());
    }

    #[test]
    fn medical_alert_item_omits_severity_when_absent() {
        let without = serde_json::to_value(MedicalAlertItem {
            kind: "allergie".into(),
            label: "latex".into(),
            severity: None,
        })
        .expect("json");
        assert_eq!(without, json!({"kind": "allergie", "label": "latex"}));
        let with = serde_json::to_value(MedicalAlertItem {
            kind: "allergie".into(),
            label: "pénicilline".into(),
            severity: Some("high".into()),
        })
        .expect("json");
        assert_eq!(
            with,
            json!({"kind": "allergie", "label": "pénicilline", "severity": "high"})
        );
    }
}
