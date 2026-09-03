//! Demandes de visite côté INFIRMIÈRE : offres reçues, accepter (premier-gagne),
//! refuser, transitions en route → arrivée → terminée.
//!
//! Quoi/Quand : l'infirmière en ligne voit ses offres (`GET /v1/nurse/offers`),
//! en accepte une (`accept` → `claim_visit`, verrou de ligne, premier-accepté-
//! gagne, les offres sœurs expirent), puis fait avancer la visite. Le patient est
//! notifié à chaque transition (in-app + WS).
//! Pourquoi : clone du helper `pharmacy_transition` (0124) sans l'audit cabinet
//! (une visite n'a pas de tenant cabinet). Modes d'échec : mauvais statut → 409 ;
//! hors tenant / inexistante → 404 ; offre déjà prise → 409.

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, State},
    Json,
};
use sqlx::Row;
use uuid::Uuid;

use crate::auth::{AppError, NurseMemberClaims};
use crate::nurse::requests::{visit_from_row, VisitDto, VISIT_COLUMNS};
use crate::{notify, realtime::WsHub, AppState, JobDispatcher};

/// `GET /v1/nurse/offers` — demandes actuellement offertes à cette infirmière.
///
/// La RLS `visit_request_nurse_select` laisse voir les demandes dont une offre
/// `pending` cible le tenant courant (jointure explicite ci-dessous pour ne
/// remonter QUE les offres, pas les visites déjà acceptées).
pub async fn list_nurse_offers(
    State(state): State<AppState>,
    claims: NurseMemberClaims,
) -> Result<Json<Vec<VisitDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_nurse_guc(&mut tx, claims.nurse_id).await?;

    let rows = sqlx::query(&format!(
        "SELECT {cols} FROM visit_request vr \
         JOIN visit_offer vo ON vo.visit_request_id = vr.id \
         WHERE vo.nurse_id = $1 AND vo.status = 'pending' AND vr.status = 'offered' \
         ORDER BY vo.offered_at DESC",
        cols = VISIT_COLUMNS
            .split(", ")
            .map(|c| format!("vr.{c}"))
            .collect::<Vec<_>>()
            .join(", "),
    ))
    .bind(claims.nurse_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(visit_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(data))
}

/// `GET /v1/nurse/visits` — visite en cours de l'infirmière (`accepted`,
/// `en_route` ou `arrived`), s'il y en a une. Renvoie `null` (jamais 404) en
/// l'absence de visite en cours : c'est un état normal, pas une erreur.
///
/// #6244 : seule la réponse de `accept` alimentait `activeVisit` côté app, qui
/// la perdait donc dès que le cubit était recréé (redémarrage, retour au
/// premier plan) — la visite restait bloquée en `accepted` sans aucun moyen de
/// la retrouver. Cette route permet à l'app de la recharger au démarrage,
/// comme elle recharge déjà le profil et les offres.
pub async fn get_active_visit(
    State(state): State<AppState>,
    claims: NurseMemberClaims,
) -> Result<Json<Option<VisitDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_nurse_guc(&mut tx, claims.nurse_id).await?;

    let row = sqlx::query(&format!(
        "SELECT {VISIT_COLUMNS} FROM visit_request \
         WHERE nurse_id = $1 AND status = ANY($2) \
         ORDER BY accepted_at DESC LIMIT 1",
    ))
    .bind(claims.nurse_id)
    .bind(&["accepted", "en_route", "arrived"][..])
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(row.as_ref().map(visit_from_row).transpose()?))
}

/// `POST /v1/nurse/visits/:id/accept` — accepte une offre (premier-gagne).
pub async fn accept_visit(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: NurseMemberClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<VisitDto>, AppError> {
    // claim_visit est SECURITY DEFINER (bypass RLS) : appel direct, pas de GUC.
    let result: String = sqlx::query_scalar("SELECT claim_visit($1, $2)")
        .bind(id)
        .bind(claims.nurse_id)
        .fetch_one(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;

    match result.as_str() {
        "accepted" => {}
        "not_found" | "no_offer" => return Err(AppError::NotFound),
        // "invalid_status" (demande déjà prise / plus offerte, y compris rejeu
        // d'un accept déjà traité) ou toute autre valeur inattendue : 409.
        _ => return Err(AppError::InvalidStatus),
    }

    // Relit la visite sous le GUC infirmière + notifie le patient.
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_nurse_guc(&mut tx, claims.nurse_id).await?;
    let row = sqlx::query(&format!(
        "SELECT {VISIT_COLUMNS} FROM visit_request WHERE id = $1",
    ))
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let visit = visit_from_row(&row)?;
    let pushed = notify_patient_of(&mut tx, id, "accepted").await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    if let Some((app_user_id, notification_id)) = pushed {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    publish_visit(&hub, claims.nurse_id, id, &visit, "accepted");
    tracing::info!(visit_request_id = %id, nurse_id = %claims.nurse_id, "visit accepted");
    Ok(Json(visit))
}

/// `POST /v1/nurse/offers/:id/decline` — retire l'offre de la file de l'infirmière.
///
/// `decline_visit_offer` (migration 0236) décline PUIS résout la demande dans
/// le même appel SQL si c'était sa dernière offre pending (re-fanout vers
/// d'autres infirmières proches en ligne, ou passage à `expired` si aucune
/// n'est disponible) — #5730 : sans ça, `visit_request.status` restait
/// bloqué à `offered` indéfiniment, sans aucun signal pour le patient.
///
/// La notification (`apply_settlement`) est volontairement best-effort après
/// coup : le déclin + sa résolution sont déjà commités en base à ce point, un
/// échec de notification ne doit pas transformer un déclin réussi en 500 (ni
/// risquer qu'une infirmière retente et tombe sur un 404 `not_found` alors
/// que son déclin a bien eu lieu).
pub async fn decline_offer(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: NurseMemberClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    let row = sqlx::query(
        "SELECT result, outcome, new_nurse_ids, patient_account_id \
         FROM decline_visit_offer($1, $2)",
    )
    .bind(id)
    .bind(claims.nurse_id)
    .fetch_one(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let result: String = row.try_get("result").map_err(|_| AppError::Internal)?;
    if result == "not_found" {
        return Err(AppError::NotFound);
    }

    let outcome: String = row.try_get("outcome").map_err(|_| AppError::Internal)?;
    let new_nurse_ids: Option<Vec<Uuid>> = row
        .try_get("new_nurse_ids")
        .map_err(|_| AppError::Internal)?;
    let patient_account_id: Option<Uuid> = row
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;

    if let Err(err) = crate::visit_offer_expiry::apply_settlement(
        &state.db,
        Some(&hub),
        dispatcher.as_ref(),
        id,
        &outcome,
        new_nurse_ids.as_deref().unwrap_or_default(),
        patient_account_id,
    )
    .await
    {
        tracing::warn!(
            visit_request_id = %id, nurse_id = %claims.nurse_id, error = ?err,
            "decline_offer: notification post-résolution en échec (déclin déjà commité)"
        );
    }

    Ok(Json(serde_json::json!({ "status": "declined" })))
}

/// `POST /v1/nurse/visits/:id/en-route` — accepted → en_route.
pub async fn en_route_visit(
    state: State<AppState>,
    hub: Extension<Arc<WsHub>>,
    dispatcher: Extension<Arc<dyn JobDispatcher>>,
    claims: NurseMemberClaims,
    id: Path<Uuid>,
) -> Result<Json<VisitDto>, AppError> {
    nurse_transition(
        state,
        hub,
        dispatcher,
        claims,
        id,
        &["accepted"],
        "en_route",
        "en_route_at",
    )
    .await
}

/// `POST /v1/nurse/visits/:id/arrived` — en_route → arrived.
pub async fn arrived_visit(
    state: State<AppState>,
    hub: Extension<Arc<WsHub>>,
    dispatcher: Extension<Arc<dyn JobDispatcher>>,
    claims: NurseMemberClaims,
    id: Path<Uuid>,
) -> Result<Json<VisitDto>, AppError> {
    nurse_transition(
        state,
        hub,
        dispatcher,
        claims,
        id,
        &["en_route"],
        "arrived",
        "arrived_at",
    )
    .await
}

/// `POST /v1/nurse/visits/:id/done` — arrived → done (visite terminée).
pub async fn done_visit(
    state: State<AppState>,
    hub: Extension<Arc<WsHub>>,
    dispatcher: Extension<Arc<dyn JobDispatcher>>,
    claims: NurseMemberClaims,
    id: Path<Uuid>,
) -> Result<Json<VisitDto>, AppError> {
    nurse_transition(
        state,
        hub,
        dispatcher,
        claims,
        id,
        &["arrived"],
        "done",
        "done_at",
    )
    .await
}

// ── Helpers ────────────────────────────────────────────────────────────────────

async fn set_nurse_guc(conn: &mut sqlx::PgConnection, nurse_id: Uuid) -> Result<(), AppError> {
    sqlx::query("SELECT set_config('app.current_nurse_id', $1, true)")
        .bind(nurse_id.to_string())
        .execute(&mut *conn)
        .await
        .map_err(|_| AppError::Internal)?;
    Ok(())
}

/// Notifie le patient d'une visite d'un changement de statut (in-app + push).
async fn notify_patient_of(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    visit_id: Uuid,
    status: &str,
) -> Result<Option<(Uuid, Uuid)>, AppError> {
    let account_id: Uuid =
        sqlx::query_scalar("SELECT patient_account_id FROM visit_request WHERE id = $1")
            .bind(visit_id)
            .fetch_one(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;
    notify::notify_patient_account(
        tx,
        account_id,
        "visit_status_changed",
        "Votre visite a été mise à jour",
        serde_json::json!({ "visit_request_id": visit_id, "status": status }),
    )
    .await
}

/// Publie l'événement de statut sur les canaux WS infirmière + patient.
fn publish_visit(hub: &Arc<WsHub>, nurse_id: Uuid, visit_id: Uuid, visit: &VisitDto, status: &str) {
    hub.publish_named(
        &format!("nurse_visits:{nurse_id}"),
        notify::order_event(&format!("nurse_visits:{nurse_id}"), visit_id, status),
    );
    // Le canal patient est indexé sur son compte : on ne le connaît pas ici sans
    // relire ; on republie côté nurse. Le patient reçoit la notif in-app (push).
    let _ = visit;
}

/// Transition gardée d'une visite par l'infirmière assignée. Pose le GUC,
/// applique l'UPDATE borné au statut attendu, distingue 404/409, notifie le
/// patient + WS. Clone allégé de `pharmacy_transition` (sans audit cabinet).
#[allow(clippy::too_many_arguments)]
async fn nurse_transition(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: NurseMemberClaims,
    Path(id): Path<Uuid>,
    expected: &[&str],
    new_status: &str,
    ts_column: &str,
) -> Result<Json<VisitDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_nurse_guc(&mut tx, claims.nurse_id).await?;

    // ts_column est une constante interne (jamais du client) → interpolation sûre.
    let row = sqlx::query(&format!(
        "UPDATE visit_request \
         SET status = $2, {ts_column} = now(), updated_at = now() \
         WHERE id = $1 AND nurse_id = $3 AND status = ANY($4) \
         RETURNING {VISIT_COLUMNS}",
    ))
    .bind(id)
    .bind(new_status)
    .bind(claims.nurse_id)
    .bind(expected)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        let exists = sqlx::query("SELECT 1 FROM visit_request WHERE id = $1")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        tx.rollback().await.ok();
        return Err(if exists.is_none() {
            AppError::NotFound
        } else {
            AppError::InvalidStatus
        });
    };
    let visit = visit_from_row(&row)?;
    let pushed = notify_patient_of(&mut tx, id, new_status).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    if let Some((app_user_id, notification_id)) = pushed {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    publish_visit(&hub, claims.nurse_id, id, &visit, new_status);
    Ok(Json(visit))
}
