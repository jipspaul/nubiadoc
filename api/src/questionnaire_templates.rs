//! Handlers `questionnaire_template` (#7159, DP-F21.b) : `GET`/`POST
//! /v1/cabinet/questionnaire-templates`, `PATCH`/`DELETE
//! /v1/cabinet/questionnaire-templates/:id`.
//!
//! S'appuie sur `questionnaire_template` (migration 0294, #7160) : catalogue
//! global seedé (`cabinet_id IS NULL`) + variante propre au cabinet, même
//! modèle RLS (`tenant_isolation` + `global_template_read`) que
//! `consent_template`/`prescription_template` — cf. `consent_templates.rs`.
//!
//! Un cabinet n'a qu'UN SEUL modèle actif à la fois (contrairement à
//! `consent_template`, qui distingue plusieurs lignées par
//! `act_category`) : `resolve_active_questionnaire_template` (utilisé par
//! `medical_questionnaire.rs` pour servir le schéma actif au patient) prend
//! la ligne active du cabinet si elle existe, sinon le standard global — une
//! seconde lignée créée par un second `POST` rendrait ce choix ambigu, d'où
//! `QuestionnaireTemplateAlreadyExists` (#7159) tant qu'un modèle actif
//! existe déjà pour ce cabinet.
//!
//! `PATCH` suit la même doctrine de versionnage que `consent_templates.rs`
//! (jamais d'édition en place) : désactive la version courante et insère
//! `version + 1` — une soumission déjà faite référence `(template_id,
//! version)` figés (migration 0294) et ne doit jamais voir son schéma
//! changer rétroactivement sous elle. `DELETE` désactive simplement le
//! modèle du cabinet (`is_active = false`, pas de suppression physique : la
//! ligne reste nécessaire aux soumissions déjà faites contre elle via la FK
//! `medical_questionnaire_submission.template_id`) — le cabinet retombe sur
//! le standard global.
//!
//! `schema` : liste de questions `{key, type, label, options, condition,
//! safety_flag, required}` (voir migration 0294 pour `key`/`type`/`label`/
//! `options`/`condition`/`safety_flag` ; `required` est un ajout #7159, cf.
//! `QuestionnaireQuestion`). `parse_questionnaire_schema` valide la forme à
//! l'écriture (`POST`/`PATCH`) ; `validate_submission_against_schema` (appelé
//! par `medical_questionnaire.rs`) valide les réponses patient contre un
//! schéma déjà persisté (donc déjà valide par construction).

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    text_validation, AppState,
};

/// Plafond métier (même doctrine que `cr_templates::MAX_CR_TEMPLATE_TITLE_LEN`).
const MAX_TITLE_LEN: usize = 200;
/// Types de question reconnus par le validateur (#7159 v1). Un type inconnu
/// est refusé à l'écriture du modèle plutôt que d'être stocké puis ignoré
/// silencieusement à la validation des réponses.
const VALID_QUESTION_TYPES: &[&str] = &["text", "boolean", "select"];

// ── Schéma : structures + validateurs ───────────────────────────────────────

/// Condition d'affichage/exigibilité d'une question — n'est prise en compte
/// (côté patient comme côté validation) que si `payload[key] == equals`.
#[derive(Deserialize)]
pub struct QuestionnaireCondition {
    pub key: String,
    pub equals: Value,
}

/// Une question du schéma (migration 0294 + `required`, ajout #7159).
/// `required` par défaut à `false` — nécessaire pour que le standard seedé
/// (qui n'a pas ce champ) reste rétro-compatible avec les soumissions déjà
/// faites contre lui (item 2 de la procédure #7159) : rien ne devient
/// obligatoire tant qu'un auteur de modèle ne le déclare pas explicitement.
#[derive(Deserialize)]
pub struct QuestionnaireQuestion {
    pub key: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub label: String,
    #[serde(default)]
    pub options: Option<Vec<String>>,
    #[serde(default)]
    pub condition: Option<QuestionnaireCondition>,
    /// Accepté et validé (type bool) à l'écriture du modèle — pas encore
    /// consommé côté logique métier dans cette version (#7159 v1).
    #[allow(dead_code)]
    #[serde(default)]
    pub safety_flag: bool,
    #[serde(default)]
    pub required: bool,
}

/// Valide la FORME d'un schéma soumis à l'écriture d'un modèle
/// (`POST`/`PATCH`) : liste non vide, clés non vides et uniques, `type`
/// reconnu, `select` porte des `options` non vides, `condition.key`
/// référence une question existante du même schéma. `422` sinon.
pub(crate) fn parse_questionnaire_schema(
    schema: &Value,
) -> Result<Vec<QuestionnaireQuestion>, AppError> {
    let Value::Array(items) = schema else {
        return Err(AppError::ValidationError);
    };
    if items.is_empty() {
        return Err(AppError::ValidationError);
    }
    text_validation::reject_nul_byte_in_json(schema)?;

    let questions: Vec<QuestionnaireQuestion> =
        serde_json::from_value(schema.clone()).map_err(|_| AppError::ValidationError)?;

    let mut seen_keys = std::collections::HashSet::new();
    for question in &questions {
        if question.key.trim().is_empty() || question.label.trim().is_empty() {
            return Err(AppError::ValidationError);
        }
        if !seen_keys.insert(question.key.as_str()) {
            return Err(AppError::ValidationError);
        }
        if !VALID_QUESTION_TYPES.contains(&question.kind.as_str()) {
            return Err(AppError::ValidationError);
        }
        if question.kind == "select" && question.options.as_ref().is_none_or(|o| o.is_empty()) {
            return Err(AppError::ValidationError);
        }
        if let Some(condition) = &question.condition {
            if !questions.iter().any(|other| other.key == condition.key) {
                return Err(AppError::ValidationError);
            }
        }
    }

    Ok(questions)
}

fn validate_answer_type(question: &QuestionnaireQuestion, value: &Value) -> Result<(), AppError> {
    match question.kind.as_str() {
        "boolean" => {
            if !value.is_boolean() {
                return Err(AppError::QuestionnaireSchemaViolation(format!(
                    "Réponse invalide pour « {} » : un booléen est attendu.",
                    question.key
                )));
            }
        }
        "text" => match value {
            // Chaîne : cas nominal. Tableau/objet : formes libres historiques
            // du questionnaire pré-#7159 (#6917, `questionnaire_entries` dans
            // `medical_questionnaire.rs`) — un champ `text` type "allergies"/
            // "traitement en cours" continue d'accepter une liste d'entrées
            // structurées, pas seulement une chaîne unique (compatibilité
            // ascendante avec les soumissions/tests existants).
            Value::String(s) => {
                if question.required && s.trim().is_empty() {
                    return Err(AppError::QuestionnaireSchemaViolation(format!(
                        "Réponse requise manquante : {}",
                        question.key
                    )));
                }
            }
            Value::Array(items) => {
                if question.required && items.is_empty() {
                    return Err(AppError::QuestionnaireSchemaViolation(format!(
                        "Réponse requise manquante : {}",
                        question.key
                    )));
                }
            }
            Value::Object(map) => {
                if question.required && map.is_empty() {
                    return Err(AppError::QuestionnaireSchemaViolation(format!(
                        "Réponse requise manquante : {}",
                        question.key
                    )));
                }
            }
            _ => {
                return Err(AppError::QuestionnaireSchemaViolation(format!(
                    "Réponse invalide pour « {} » : un texte est attendu.",
                    question.key
                )));
            }
        },
        "select" => {
            let Some(text) = value.as_str() else {
                return Err(AppError::QuestionnaireSchemaViolation(format!(
                    "Réponse invalide pour « {} » : une valeur parmi les options est attendue.",
                    question.key
                )));
            };
            let options = question.options.as_deref().unwrap_or(&[]);
            if !options.iter().any(|option| option == text) {
                return Err(AppError::QuestionnaireSchemaViolation(format!(
                    "Réponse invalide pour « {} » : valeur hors des options proposées.",
                    question.key
                )));
            }
        }
        // Type inconnu : ne peut pas arriver sur un schéma persisté (déjà
        // filtré par `parse_questionnaire_schema` à l'écriture du modèle) —
        // accepté sans validation de type par défense en profondeur plutôt
        // que de faire échouer une soumission patient sur un souci de modèle.
        _ => {}
    }
    Ok(())
}

/// Valide un `payload` de soumission contre un schéma déjà persisté (donc
/// déjà valide par construction, cf. `parse_questionnaire_schema`).
///
/// `require_complete` : `false` pour un brouillon en cours de saisie (seul
/// le TYPE des réponses déjà fournies est vérifié, rien n'est exigé) ;
/// `true` à la soumission finale (`submit: true`), où les questions
/// `required` — et dont la `condition` éventuelle est satisfaite — doivent
/// avoir une réponse non vide. Une question dont la `condition` n'est PAS
/// satisfaite est ignorée dans les deux cas (logique conditionnelle, #7159).
pub(crate) fn validate_submission_against_schema(
    questions: &[QuestionnaireQuestion],
    payload: &Value,
    require_complete: bool,
) -> Result<(), AppError> {
    let Some(payload_obj) = payload.as_object() else {
        return Err(AppError::ValidationError);
    };

    for question in questions {
        let condition_met = match &question.condition {
            None => true,
            Some(condition) => payload_obj.get(&condition.key) == Some(&condition.equals),
        };
        if !condition_met {
            continue;
        }

        match payload_obj.get(&question.key) {
            None | Some(Value::Null) => {
                if require_complete && question.required {
                    return Err(AppError::QuestionnaireSchemaViolation(format!(
                        "Réponse requise manquante : {}",
                        question.key
                    )));
                }
            }
            Some(value) => validate_answer_type(question, value)?,
        }
    }

    Ok(())
}

// ── GET /v1/cabinet/questionnaire-templates ─────────────────────────────────

/// Un modèle de questionnaire, vu du cabinet courant.
#[derive(Serialize)]
pub struct QuestionnaireTemplateDto {
    pub id: Uuid,
    pub title: String,
    pub schema: Value,
    pub version: i32,
    /// `true` : modèle global seedé (`cabinet_id IS NULL`), lecture seule.
    pub is_global: bool,
    pub created_at: String,
}

fn row_to_template_dto(row: &sqlx::postgres::PgRow) -> Result<QuestionnaireTemplateDto, AppError> {
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    Ok(QuestionnaireTemplateDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        title: row.try_get("title").map_err(|_| AppError::Internal)?,
        schema: row.try_get("schema").map_err(|_| AppError::Internal)?,
        version: row.try_get("version").map_err(|_| AppError::Internal)?,
        is_global: row.try_get("is_global").map_err(|_| AppError::Internal)?,
        created_at: created_at.to_rfc3339(),
    })
}

/// `GET /v1/cabinet/questionnaire-templates` — liste les modèles actifs
/// visibles (catalogue global + modèle propre au cabinet s'il existe).
///
/// Praticien uniquement. RLS scopée via `app.current_cabinet_id`
/// (`tenant_isolation` OR `global_template_read`), seules les versions
/// actives (`is_active = true`) sont listées.
pub async fn list_questionnaire_templates(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
) -> Result<Json<Vec<QuestionnaireTemplateDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, title, schema, version, (cabinet_id IS NULL) AS is_global, created_at \
         FROM questionnaire_template \
         WHERE is_active = true \
         ORDER BY (cabinet_id IS NULL) ASC, title",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let templates = rows
        .iter()
        .map(row_to_template_dto)
        .collect::<Result<Vec<_>, _>>()?;

    Ok(Json(templates))
}

// ── POST /v1/cabinet/questionnaire-templates ────────────────────────────────

/// Corps de `POST /v1/cabinet/questionnaire-templates`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateQuestionnaireTemplateBody {
    pub title: String,
    pub schema: Value,
}

/// Réponse de `POST`/`PATCH /v1/cabinet/questionnaire-templates`.
#[derive(Serialize)]
pub struct QuestionnaireTemplateIdResponse {
    pub id: Uuid,
    pub version: i32,
}

/// `POST /v1/cabinet/questionnaire-templates` — crée le modèle propre au
/// cabinet.
///
/// `409 questionnaire_template_already_exists` si le cabinet a déjà un
/// modèle actif : il doit faire évoluer celui-ci via `PATCH` (voir doc de
/// module — un cabinet n'a qu'une seule lignée active). `title` non vide/
/// blanc et borné, `schema` structurellement valide (voir
/// `parse_questionnaire_schema`) → `422` sinon.
pub async fn create_questionnaire_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<CreateQuestionnaireTemplateBody>,
) -> Result<(StatusCode, Json<QuestionnaireTemplateIdResponse>), AppError> {
    if body.title.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    text_validation::reject_nul_byte(&body.title)?;
    text_validation::validate_max_len(&body.title, MAX_TITLE_LEN)?;
    parse_questionnaire_schema(&body.schema)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query(
        "SELECT 1 FROM questionnaire_template WHERE cabinet_id = $1 AND is_active = true",
    )
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if existing.is_some() {
        return Err(AppError::QuestionnaireTemplateAlreadyExists);
    }

    let row = sqlx::query(
        "INSERT INTO questionnaire_template (cabinet_id, title, schema) \
         VALUES ($1, $2, $3) \
         RETURNING id, version",
    )
    .bind(claims.cabinet_id)
    .bind(body.title.trim())
    .bind(&body.schema)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let version: i32 = row.try_get("version").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        template_id = %id,
        "questionnaire template created"
    );

    Ok((
        StatusCode::CREATED,
        Json(QuestionnaireTemplateIdResponse { id, version }),
    ))
}

// ── PATCH /v1/cabinet/questionnaire-templates/:id ───────────────────────────

/// Corps de `PATCH /v1/cabinet/questionnaire-templates/:id`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchQuestionnaireTemplateBody {
    pub title: Option<String>,
    pub schema: Option<Value>,
}

/// `PATCH /v1/cabinet/questionnaire-templates/:id` — fait évoluer le modèle
/// du cabinet.
///
/// Champs absents = inchangés. Modèle absent, hors tenant, ou global
/// (`cabinet_id IS NULL`, non éditable par un cabinet) → `404`. Comme
/// `consent_templates::patch_consent_template` : pas de changement réel
/// (mêmes valeurs, ou corps `{}`) → no-op, `id`/`version` courants renvoyés
/// tels quels. Sinon désactive la version courante et insère `version + 1` ;
/// la réponse porte l'`id` de la NOUVELLE ligne.
pub async fn patch_questionnaire_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchQuestionnaireTemplateBody>,
) -> Result<Json<QuestionnaireTemplateIdResponse>, AppError> {
    if body.title.as_deref().is_some_and(|s| s.trim().is_empty()) {
        return Err(AppError::ValidationError);
    }
    if let Some(schema) = &body.schema {
        parse_questionnaire_schema(schema)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let current = sqlx::query(
        "SELECT title, schema, version FROM questionnaire_template \
         WHERE id = $1 AND cabinet_id = $2 AND is_active = true",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cur_title: String = current.try_get("title").map_err(|_| AppError::Internal)?;
    let cur_schema: Value = current.try_get("schema").map_err(|_| AppError::Internal)?;
    let cur_version: i32 = current.try_get("version").map_err(|_| AppError::Internal)?;

    let new_title = body
        .title
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| cur_title.clone());
    let new_schema = body.schema.unwrap_or_else(|| cur_schema.clone());

    text_validation::reject_nul_byte(&new_title)?;
    text_validation::validate_max_len(&new_title, MAX_TITLE_LEN)?;

    if new_title == cur_title && new_schema == cur_schema {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(QuestionnaireTemplateIdResponse {
            id,
            version: cur_version,
        }));
    }

    sqlx::query(
        "UPDATE questionnaire_template SET is_active = false WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let new_version = cur_version + 1;
    let inserted = sqlx::query(
        "INSERT INTO questionnaire_template (cabinet_id, title, schema, version) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id, version",
    )
    .bind(claims.cabinet_id)
    .bind(&new_title)
    .bind(&new_schema)
    .bind(new_version)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let new_id: Uuid = inserted.try_get("id").map_err(|_| AppError::Internal)?;
    let returned_version: i32 = inserted
        .try_get("version")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        old_template_id = %id,
        new_template_id = %new_id,
        version = returned_version,
        "questionnaire template patched (new version)"
    );

    Ok(Json(QuestionnaireTemplateIdResponse {
        id: new_id,
        version: returned_version,
    }))
}

// ── DELETE /v1/cabinet/questionnaire-templates/:id ──────────────────────────

/// `DELETE /v1/cabinet/questionnaire-templates/:id` — désactive le modèle du
/// cabinet (`is_active = false`, jamais de suppression physique : la ligne
/// reste référencée par les soumissions déjà faites contre elle, FK
/// `medical_questionnaire_submission.template_id`). Le cabinet retombe sur
/// le standard global pour les prochaines soumissions
/// (`resolve_active_questionnaire_template`). Modèle absent, hors tenant,
/// global, ou déjà inactif → `404`.
pub async fn delete_questionnaire_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let deactivated = sqlx::query(
        "UPDATE questionnaire_template SET is_active = false \
         WHERE id = $1 AND cabinet_id = $2 AND is_active = true \
         RETURNING id",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if deactivated.is_none() {
        return Err(AppError::NotFound);
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        template_id = %id,
        "questionnaire template deactivated"
    );

    Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn sample_schema() -> Value {
        json!([
            {
                "key": "allergies", "type": "text", "label": "Allergies ?",
                "options": null, "condition": null, "safety_flag": true, "required": true
            },
            {
                "key": "diabete", "type": "boolean", "label": "Diabétique ?",
                "options": null, "condition": null, "safety_flag": false
            },
            {
                "key": "diabete_type", "type": "select", "label": "Type ?",
                "options": ["Type 1", "Type 2"],
                "condition": {"key": "diabete", "equals": true},
                "safety_flag": false, "required": true
            }
        ])
    }

    #[test]
    fn parse_questionnaire_schema_accepts_valid_schema() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        assert_eq!(questions.len(), 3);
        assert!(questions[0].required);
        assert!(!questions[1].required);
    }

    #[test]
    fn parse_questionnaire_schema_rejects_empty_list() {
        assert!(parse_questionnaire_schema(&json!([])).is_err());
    }

    #[test]
    fn parse_questionnaire_schema_rejects_duplicate_keys() {
        let schema = json!([
            {
                "key": "a", "type": "text", "label": "A",
                "options": null, "condition": null, "safety_flag": false
            },
            {
                "key": "a", "type": "text", "label": "A bis",
                "options": null, "condition": null, "safety_flag": false
            }
        ]);
        assert!(parse_questionnaire_schema(&schema).is_err());
    }

    #[test]
    fn parse_questionnaire_schema_rejects_unknown_type() {
        let schema = json!([
            {
                "key": "a", "type": "date", "label": "A",
                "options": null, "condition": null, "safety_flag": false
            }
        ]);
        assert!(parse_questionnaire_schema(&schema).is_err());
    }

    #[test]
    fn parse_questionnaire_schema_rejects_select_without_options() {
        let schema = json!([
            {
                "key": "a", "type": "select", "label": "A",
                "options": null, "condition": null, "safety_flag": false
            }
        ]);
        assert!(parse_questionnaire_schema(&schema).is_err());
    }

    #[test]
    fn parse_questionnaire_schema_rejects_dangling_condition() {
        let schema = json!([
            {
                "key": "a", "type": "text", "label": "A", "options": null,
                "condition": {"key": "inconnu", "equals": true},
                "safety_flag": false
            }
        ]);
        assert!(parse_questionnaire_schema(&schema).is_err());
    }

    #[test]
    fn validate_submission_accepts_partial_draft_without_required_fields() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        let payload = json!({});
        assert!(validate_submission_against_schema(&questions, &payload, false).is_ok());
    }

    #[test]
    fn validate_submission_rejects_missing_required_field_on_submit() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        let payload = json!({});
        let err = validate_submission_against_schema(&questions, &payload, true).unwrap_err();
        assert!(matches!(err, AppError::QuestionnaireSchemaViolation(_)));
    }

    #[test]
    fn validate_submission_rejects_wrong_type() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        let payload = json!({"allergies": "aucune", "diabete": "oui"});
        let err = validate_submission_against_schema(&questions, &payload, false).unwrap_err();
        assert!(matches!(err, AppError::QuestionnaireSchemaViolation(_)));
    }

    #[test]
    fn validate_submission_ignores_unmet_conditional_requirement() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        // diabete = false → diabete_type (required) n'est pas exigé.
        let payload = json!({"allergies": "aucune", "diabete": false});
        assert!(validate_submission_against_schema(&questions, &payload, true).is_ok());
    }

    #[test]
    fn validate_submission_requires_conditional_field_when_condition_met() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        let payload = json!({"allergies": "aucune", "diabete": true});
        let err = validate_submission_against_schema(&questions, &payload, true).unwrap_err();
        assert!(matches!(err, AppError::QuestionnaireSchemaViolation(_)));
    }

    #[test]
    fn validate_submission_accepts_complete_payload() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        let payload = json!({"allergies": "aucune", "diabete": true, "diabete_type": "Type 2"});
        assert!(validate_submission_against_schema(&questions, &payload, true).is_ok());
    }

    #[test]
    fn validate_submission_rejects_select_value_out_of_options() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        let payload = json!({"allergies": "aucune", "diabete": true, "diabete_type": "Type 3"});
        let err = validate_submission_against_schema(&questions, &payload, true).unwrap_err();
        assert!(matches!(err, AppError::QuestionnaireSchemaViolation(_)));
    }

    /// #6917 : un champ `text` (ex. `allergies`) accepte aussi une liste
    /// d'entrées structurées, pas seulement une chaîne — compatibilité avec
    /// les soumissions existantes du questionnaire standard (#7159).
    #[test]
    fn validate_submission_accepts_list_and_object_for_text_field() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        let payload = json!({
            "allergies": ["latex", {"substance": "pénicilline", "severity": "high"}]
        });
        assert!(validate_submission_against_schema(&questions, &payload, false).is_ok());

        let payload = json!({"allergies": {"substance": "nickel"}});
        assert!(validate_submission_against_schema(&questions, &payload, false).is_ok());
    }

    #[test]
    fn validate_submission_rejects_number_for_text_field() {
        let questions = parse_questionnaire_schema(&sample_schema()).unwrap();
        let payload = json!({"allergies": 42});
        let err = validate_submission_against_schema(&questions, &payload, false).unwrap_err();
        assert!(matches!(err, AppError::QuestionnaireSchemaViolation(_)));
    }
}
