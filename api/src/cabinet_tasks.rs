//! Handlers `/v1/cabinet/tasks` — tâches internes assignables du cabinet
//! (#7211), sur `cabinet_task` (migration 0273, #7212) : to-do secrétariat
//! et notes à l'assistante, éventuellement liées à un patient/RDV.
//!
//! `POST /v1/appointments/:id/tasks` (raccourci « prépare le guide
//! chirurgical ») partage l'insertion avec `POST /v1/cabinet/tasks` via
//! `insert_task` — seule la résolution du patient/RDV diffère (dérivée du
//! RDV plutôt que fournie par le client).
//!
//! Assignation → notification in-app + push à l'assigné (`notify::notify_user`,
//! kind `task_assigned`, non mappé dans `notify::preference_category` donc
//! jamais bloqué par les préférences — fail-open documenté). Pas de
//! notification sur réassignation via `PATCH` (hors scope #7211 : seule la
//! création notifie).

use std::collections::HashMap;

use axum::{
    extract::{Extension, Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    notify, text_validation, AppState, JobDispatcher,
};

const VALID_STATUSES: [&str; 3] = ["open", "done", "cancelled"];

/// Bornes hautes sur `title`/`description`, sur le modèle de
/// `text_validation::validate_max_len` (#7226) — 6ᵉ module livré sans cette
/// borne après #7138/#7226/#7253/#7275/#7330 (#7344).
const MAX_TASK_TITLE_LEN: usize = 200;
const MAX_TASK_DESCRIPTION_LEN: usize = 4_000;

/// Transition de statut valide via `PATCH` : seule une tâche `open` peut
/// changer de statut — même doctrine que `POST .../complete`, qui ne clôture
/// qu'une tâche `open` (`lab_work_orders.rs::is_forward_transition`, même
/// principe). Renvoyer le même statut (no-op) est toujours permis, y compris
/// sur une tâche `done`/`cancelled` (#7344 : le `PATCH` laissait rouvrir une
/// tâche `done`/`cancelled`, contournant la garde de `complete_cabinet_task`).
fn is_valid_task_status_transition(current: &str, target: &str) -> bool {
    target == current || current == "open"
}

/// Résout le nom d'un membre du cabinet (`app_user.first_name`/`last_name`)
/// pour l'affichage. RLS `app_user` self-only (policy `user_self_select`,
/// migration 0045) : même contournement (GUC reposé par user, avec cache)
/// que `cabinet_team_messages.rs::list_cabinet_team_messages`.
async fn resolve_member_name(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cache: &mut HashMap<Uuid, Option<String>>,
    user_id: Uuid,
) -> Result<Option<String>, AppError> {
    if let Some(name) = cache.get(&user_id) {
        return Ok(name.clone());
    }

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query("SELECT first_name, last_name FROM app_user WHERE id = $1")
        .bind(user_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let name = row.and_then(|row| {
        let first_name: Option<String> = row.try_get("first_name").ok()?;
        let last_name: Option<String> = row.try_get("last_name").ok()?;
        let full_name = [first_name, last_name]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>()
            .join(" ");
        (!full_name.trim().is_empty()).then_some(full_name)
    });
    cache.insert(user_id, name.clone());
    Ok(name)
}

/// Vérifie que l'assigné/patient/RDV, quand fournis, appartiennent bien au
/// cabinet — et que le RDV appartient au même patient si les deux sont
/// fournis (#4353, même garde que `lab_work_orders.rs::create_lab_work_order`).
/// Pré-vérifié pour ne pas laisser remonter la violation de FK composite
/// (migration 0273) en `500`.
async fn validate_task_refs(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    assignee_user_id: Option<Uuid>,
    patient_id: Option<Uuid>,
    appointment_id: Option<Uuid>,
) -> Result<(), AppError> {
    if let Some(user_id) = assignee_user_id {
        let exists =
            sqlx::query("SELECT 1 FROM cabinet_membership WHERE cabinet_id = $1 AND user_id = $2")
                .bind(cabinet_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await
                .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    if let Some(patient_id) = patient_id {
        let exists = sqlx::query("SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2")
            .bind(patient_id)
            .bind(cabinet_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    if let Some(appointment_id) = appointment_id {
        let exists = match patient_id {
            Some(patient_id) => sqlx::query(
                "SELECT 1 FROM appointment WHERE id = $1 AND cabinet_id = $2 AND patient_id = $3",
            )
            .bind(appointment_id)
            .bind(cabinet_id)
            .bind(patient_id)
            .fetch_optional(&mut **tx)
            .await,
            None => {
                sqlx::query("SELECT 1 FROM appointment WHERE id = $1 AND cabinet_id = $2")
                    .bind(appointment_id)
                    .bind(cabinet_id)
                    .fetch_optional(&mut **tx)
                    .await
            }
        }
        .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    Ok(())
}

/// INSERT partagé par `create_cabinet_task` et `create_appointment_task`.
/// Notifie l'assigné (`task_assigned`) si `assignee_user_id` est fourni ;
/// retourne `(task_id, Some((assignee, notification_id)))` quand le push
/// doit être enfilé après commit (pattern `appointments_create.rs`), `None`
/// sinon (pas d'assigné, ou catégorie désactivée par l'assigné).
#[allow(clippy::too_many_arguments)]
async fn insert_task(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    created_by: Uuid,
    title: &str,
    description: Option<&str>,
    assignee_user_id: Option<Uuid>,
    patient_id: Option<Uuid>,
    appointment_id: Option<Uuid>,
    due_date: Option<chrono::NaiveDate>,
) -> Result<(Uuid, Option<(Uuid, Uuid)>), AppError> {
    validate_task_refs(tx, cabinet_id, assignee_user_id, patient_id, appointment_id).await?;

    let row = sqlx::query(
        "INSERT INTO cabinet_task \
         (cabinet_id, title, description, assignee_user_id, patient_id, appointment_id, due_date, created_by) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) \
         RETURNING id",
    )
    .bind(cabinet_id)
    .bind(title)
    .bind(description)
    .bind(assignee_user_id)
    .bind(patient_id)
    .bind(appointment_id)
    .bind(due_date)
    .bind(created_by)
    .fetch_one(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let task_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    let push_target = match assignee_user_id {
        Some(assignee) => notify::notify_user(
            tx,
            assignee,
            "task_assigned",
            "Nouvelle tâche assignée",
            serde_json::json!({ "task_id": task_id }),
        )
        .await?
        .map(|notification_id| (assignee, notification_id)),
        None => None,
    };

    Ok((task_id, push_target))
}

// ── GET/POST /v1/cabinet/tasks ────────────────────────────────────────────

/// Query de `GET /v1/cabinet/tasks`.
#[derive(Deserialize)]
pub struct ListCabinetTasksQuery {
    pub assignee_id: Option<Uuid>,
    pub status: Option<String>,
    pub patient_id: Option<Uuid>,
}

/// Une tâche du cabinet.
#[derive(Serialize)]
pub struct CabinetTaskItem {
    pub id: Uuid,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assignee_user_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assignee_display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub patient_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub patient_display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub appointment_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub due_date: Option<String>,
    pub status: String,
    pub created_by: Uuid,
    pub created_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub done_at: Option<String>,
}

/// `GET /v1/cabinet/tasks` — liste les tâches du cabinet, filtrable par
/// assigné/statut/patient (#7211). Tri : échéance croissante (sans échéance
/// en dernier), puis création la plus récente.
///
/// `?status=` hors `open`/`done`/`cancelled` (CHECK, migration 0273) → 422.
pub async fn list_cabinet_tasks(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(query): Query<ListCabinetTasksQuery>,
) -> Result<Json<Vec<CabinetTaskItem>>, AppError> {
    if let Some(ref status) = query.status {
        if !VALID_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT t.id, t.title, t.description, t.assignee_user_id, t.patient_id, \
                t.appointment_id, t.due_date, t.status, t.created_by, t.created_at, t.done_at, \
                p.first_name AS patient_first_name, p.last_name AS patient_last_name \
         FROM cabinet_task t \
         LEFT JOIN patient p ON p.id = t.patient_id \
         WHERE t.cabinet_id = $1 \
           AND ($2::uuid IS NULL OR t.assignee_user_id = $2) \
           AND ($3::text IS NULL OR t.status = $3) \
           AND ($4::uuid IS NULL OR t.patient_id = $4) \
         ORDER BY t.due_date ASC NULLS LAST, t.created_at DESC",
    )
    .bind(claims.cabinet_id)
    .bind(query.assignee_id)
    .bind(query.status.as_deref())
    .bind(query.patient_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut name_cache: HashMap<Uuid, Option<String>> = HashMap::new();
    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        let assignee_user_id: Option<Uuid> = row
            .try_get("assignee_user_id")
            .map_err(|_| AppError::Internal)?;
        let assignee_display_name = match assignee_user_id {
            Some(user_id) => resolve_member_name(&mut tx, &mut name_cache, user_id).await?,
            None => None,
        };

        let patient_first_name: Option<String> = row
            .try_get("patient_first_name")
            .map_err(|_| AppError::Internal)?;
        let patient_last_name: Option<String> = row
            .try_get("patient_last_name")
            .map_err(|_| AppError::Internal)?;
        let patient_display_name = match (patient_first_name, patient_last_name) {
            (Some(first), Some(last)) => Some(format!("{first} {last}")),
            _ => None,
        };

        let due_date: Option<chrono::NaiveDate> =
            row.try_get("due_date").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        let done_at: Option<chrono::DateTime<chrono::Utc>> =
            row.try_get("done_at").map_err(|_| AppError::Internal)?;

        data.push(CabinetTaskItem {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            title: row.try_get("title").map_err(|_| AppError::Internal)?,
            description: row.try_get("description").map_err(|_| AppError::Internal)?,
            assignee_user_id,
            assignee_display_name,
            patient_id: row.try_get("patient_id").map_err(|_| AppError::Internal)?,
            patient_display_name,
            appointment_id: row
                .try_get("appointment_id")
                .map_err(|_| AppError::Internal)?,
            due_date: due_date.map(|d| d.to_string()),
            status: row.try_get("status").map_err(|_| AppError::Internal)?,
            created_by: row.try_get("created_by").map_err(|_| AppError::Internal)?,
            created_at: created_at.to_rfc3339(),
            done_at: done_at.map(|d| d.to_rfc3339()),
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(data))
}

/// Body de `POST /v1/cabinet/tasks`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateCabinetTaskBody {
    pub title: String,
    pub description: Option<String>,
    pub assignee_user_id: Option<Uuid>,
    pub patient_id: Option<Uuid>,
    pub appointment_id: Option<Uuid>,
    /// Date ISO `YYYY-MM-DD`.
    pub due_date: Option<String>,
}

/// Réponse de `POST /v1/cabinet/tasks` et `POST /v1/appointments/:id/tasks`.
#[derive(Serialize)]
pub struct CreateCabinetTaskResponse {
    pub id: Uuid,
}

/// `POST /v1/cabinet/tasks` — crée une tâche (statut `open`).
///
/// `title` non vide et ≤ [`MAX_TASK_TITLE_LEN`] caractères, `description` ≤
/// [`MAX_TASK_DESCRIPTION_LEN`] caractères → 422 sinon. `due_date` doit être
/// une date ISO valide → 422 sinon. `assignee_user_id`/`patient_id`/
/// `appointment_id`, quand fournis, doivent appartenir à ce cabinet (et le
/// RDV au même patient si les deux sont fournis) → 404 sinon. Assigné fourni
/// → notifie (in-app + push) via `task_assigned`.
pub async fn create_cabinet_task(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateCabinetTaskBody>,
) -> Result<(StatusCode, Json<CreateCabinetTaskResponse>), AppError> {
    let title = body.title.trim().to_string();
    if title.is_empty() {
        return Err(AppError::ValidationError);
    }
    text_validation::reject_nul_byte(&title)?;
    text_validation::validate_max_len(&title, MAX_TASK_TITLE_LEN)?;
    if let Some(ref description) = body.description {
        text_validation::reject_nul_byte(description)?;
        text_validation::validate_max_len(description, MAX_TASK_DESCRIPTION_LEN)?;
    }
    let due_date = body
        .due_date
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (task_id, push_target) = insert_task(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &title,
        body.description.as_deref(),
        body.assignee_user_id,
        body.patient_id,
        body.appointment_id,
        due_date,
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    if let Some((assignee, notification_id)) = push_target {
        dispatcher.enqueue_push_notification(assignee, notification_id);
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        task_id = %task_id,
        "cabinet task created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateCabinetTaskResponse { id: task_id }),
    ))
}

// ── PATCH /v1/cabinet/tasks/:id ───────────────────────────────────────────

/// Body de `PATCH /v1/cabinet/tasks/:id` — édition partielle, un champ
/// absent (`None`) laisse la valeur existante inchangée (pas de moyen de
/// remettre `assignee_user_id`/`patient_id`/`appointment_id` à `null` par ce
/// biais, même limite documentée que `cabinet_quotes_patch.rs::deposit_pct`).
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchCabinetTaskBody {
    pub title: Option<String>,
    pub description: Option<String>,
    pub assignee_user_id: Option<Uuid>,
    pub patient_id: Option<Uuid>,
    pub appointment_id: Option<Uuid>,
    pub due_date: Option<String>,
    pub status: Option<String>,
}

/// Réponse de `PATCH`/`POST .../complete`.
#[derive(Serialize)]
pub struct CabinetTaskStatusResponse {
    pub id: Uuid,
    pub status: String,
}

/// `PATCH /v1/cabinet/tasks/:id` — met à jour une tâche (édition de champs
/// et/ou changement de statut, ex. `cancelled`). Tâche inexistante/hors
/// tenant → 404. `status` hors énum → 422. Changement de statut alors que la
/// tâche courante n'est pas `open` → `409 invalid_status` (même garde que
/// `POST .../complete`, cf. [`is_valid_task_status_transition`]). Passage à
/// `done` pose `done_at = now()` ; passage hors `done` remet `done_at` à
/// `null`. Pas de notification sur réassignation (hors scope #7211).
pub async fn patch_cabinet_task(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchCabinetTaskBody>,
) -> Result<Json<CabinetTaskStatusResponse>, AppError> {
    if let Some(ref status) = body.status {
        if !VALID_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
    }
    let title = body.title.as_deref().map(|t| t.trim());
    if let Some(title) = title {
        if title.is_empty() {
            return Err(AppError::ValidationError);
        }
        text_validation::reject_nul_byte(title)?;
        text_validation::validate_max_len(title, MAX_TASK_TITLE_LEN)?;
    }
    if let Some(ref description) = body.description {
        text_validation::reject_nul_byte(description)?;
        text_validation::validate_max_len(description, MAX_TASK_DESCRIPTION_LEN)?;
    }
    let due_date = body
        .due_date
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query(
        "SELECT title, description, assignee_user_id, patient_id, appointment_id, due_date, status \
         FROM cabinet_task WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let existing_title: String = existing.try_get("title").map_err(|_| AppError::Internal)?;
    let existing_description: Option<String> = existing
        .try_get("description")
        .map_err(|_| AppError::Internal)?;
    let existing_assignee: Option<Uuid> = existing
        .try_get("assignee_user_id")
        .map_err(|_| AppError::Internal)?;
    let existing_patient: Option<Uuid> = existing
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let existing_appointment: Option<Uuid> = existing
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let existing_due_date: Option<chrono::NaiveDate> = existing
        .try_get("due_date")
        .map_err(|_| AppError::Internal)?;
    let current_status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;

    let new_title = title.map(|t| t.to_string()).unwrap_or(existing_title);
    let new_description = body.description.or(existing_description);
    let new_assignee = body.assignee_user_id.or(existing_assignee);
    let new_patient = body.patient_id.or(existing_patient);
    let new_appointment = body.appointment_id.or(existing_appointment);
    let new_due_date = due_date.or(existing_due_date);
    let new_status = body.status.unwrap_or_else(|| current_status.clone());

    if !is_valid_task_status_transition(&current_status, &new_status) {
        return Err(AppError::InvalidStatus);
    }

    validate_task_refs(
        &mut tx,
        claims.cabinet_id,
        new_assignee,
        new_patient,
        new_appointment,
    )
    .await?;

    let done_at_now = new_status == "done" && current_status != "done";
    let clear_done_at = new_status != "done";

    sqlx::query(
        "UPDATE cabinet_task \
         SET title = $1, description = $2, assignee_user_id = $3, patient_id = $4, \
             appointment_id = $5, due_date = $6, status = $7, \
             done_at = CASE WHEN $8 THEN now() WHEN $9 THEN NULL ELSE done_at END \
         WHERE id = $10 AND cabinet_id = $11",
    )
    .bind(&new_title)
    .bind(&new_description)
    .bind(new_assignee)
    .bind(new_patient)
    .bind(new_appointment)
    .bind(new_due_date)
    .bind(&new_status)
    .bind(done_at_now)
    .bind(clear_done_at)
    .bind(id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        task_id = %id,
        "cabinet task updated"
    );

    Ok(Json(CabinetTaskStatusResponse {
        id,
        status: new_status,
    }))
}

// ── POST /v1/cabinet/tasks/:id/complete ───────────────────────────────────

/// `POST /v1/cabinet/tasks/:id/complete` — clôture une tâche `open` (statut
/// `done`, `done_at = now()`). Tâche inexistante/hors tenant → 404. Tâche
/// déjà `done`/`cancelled` → `409 invalid_status` (même doctrine que
/// `lab_work_orders.rs::patch_lab_work_order`).
pub async fn complete_cabinet_task(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<CabinetTaskStatusResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query("SELECT status FROM cabinet_task WHERE id = $1 AND cabinet_id = $2")
        .bind(id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
    let current_status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;
    if current_status != "open" {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query(
        "UPDATE cabinet_task SET status = 'done', done_at = now() WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        task_id = %id,
        "cabinet task completed"
    );

    Ok(Json(CabinetTaskStatusResponse {
        id,
        status: "done".to_string(),
    }))
}

// ── POST /v1/appointments/:id/tasks ───────────────────────────────────────

/// Body de `POST /v1/appointments/:id/tasks`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateAppointmentTaskBody {
    pub title: String,
    pub description: Option<String>,
    pub assignee_user_id: Option<Uuid>,
    /// Date ISO `YYYY-MM-DD`.
    pub due_date: Option<String>,
}

/// `POST /v1/appointments/:id/tasks` — raccourci qui pré-remplit
/// `patient_id`/`appointment_id` depuis le RDV (#7211, ex. « prépare le
/// guide chirurgical » depuis la fiche RDV). RDV inexistant/hors tenant →
/// 404. Mêmes règles de validation/notification que `POST /v1/cabinet/tasks`
/// (`insert_task`).
pub async fn create_appointment_task(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
    claims: ProSecretaryPlusClaims,
    Path(appointment_id): Path<Uuid>,
    Json(body): Json<CreateAppointmentTaskBody>,
) -> Result<(StatusCode, Json<CreateCabinetTaskResponse>), AppError> {
    let title = body.title.trim().to_string();
    if title.is_empty() {
        return Err(AppError::ValidationError);
    }
    text_validation::reject_nul_byte(&title)?;
    text_validation::validate_max_len(&title, MAX_TASK_TITLE_LEN)?;
    if let Some(ref description) = body.description {
        text_validation::reject_nul_byte(description)?;
        text_validation::validate_max_len(description, MAX_TASK_DESCRIPTION_LEN)?;
    }
    let due_date = body
        .due_date
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let appointment_row =
        sqlx::query("SELECT patient_id FROM appointment WHERE id = $1 AND cabinet_id = $2")
            .bind(appointment_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;
    let patient_id: Uuid = appointment_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    let (task_id, push_target) = insert_task(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &title,
        body.description.as_deref(),
        body.assignee_user_id,
        Some(patient_id),
        Some(appointment_id),
        due_date,
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    if let Some((assignee, notification_id)) = push_target {
        dispatcher.enqueue_push_notification(assignee, notification_id);
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        appointment_id = %appointment_id,
        task_id = %task_id,
        "cabinet task created from appointment"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateCabinetTaskResponse { id: task_id }),
    ))
}
