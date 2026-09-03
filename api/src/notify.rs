//! Notifications in-app + push (sans PII) pour le domaine pharmacie (lot B4).
//!
//! Insère dans `notification` (RLS user-scoped : le GUC `app.current_user_id`
//! est posé sur la valeur DB du destinataire, jamais sur une valeur client)
//! puis laisse l'appelant enfiler le push FCM via `JobDispatcher` APRÈS le
//! commit. Le payload push ne contient jamais de donnée de santé : titre
//! générique + `data {order_id, status}` (deeplink).

use sqlx::Row;
use uuid::Uuid;

use crate::auth::AppError;

/// Mapping `kind` → catégorie `user_notification_preference` (migration 0246,
/// #6257), pour le gating à l'émission (#6258). Uniquement les kinds dont la
/// catégorie destinataire pro est sans ambiguïté (ex. pas `pharmacy_order_ready`
/// : notification patient, hors périmètre des catégories pro) ; tout kind
/// absent de ce mapping n'est jamais bloqué (fail-open documenté).
fn preference_category(kind: &str) -> Option<&'static str> {
    match kind {
        "appointment_requested" | "callback_requested" => Some("rdv"),
        "quote_signed" | "pharmacy_quote_decided" => Some("devis"),
        "stock_request_received" => Some("stock"),
        "message_received" => Some("messagerie"),
        "lab_work_returned" => Some("labo"),
        "visit_offer" => Some("visites"),
        _ => None,
    }
}

/// `true` si la catégorie est autorisée pour ce destinataire. Lit
/// `user_notification_preference.inapp_<catégorie>` — défaut `true` si la
/// ligne n'existe pas encore pour ce `app_user_id` (jamais bloquant par
/// défaut, #6258). Suppose `app.current_user_id` déjà posé sur
/// `app_user_id` (policy RLS `user_notification_preference_owner_select`).
async fn category_enabled(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    app_user_id: Uuid,
    category: &str,
) -> Result<bool, AppError> {
    let column = match category {
        "rdv" => "inapp_rdv",
        "devis" => "inapp_devis",
        "stock" => "inapp_stock",
        "messagerie" => "inapp_messagerie",
        "labo" => "inapp_labo",
        "visites" => "inapp_visites",
        _ => return Ok(true),
    };
    let sql = format!(
        "SELECT COALESCE((SELECT {column} FROM user_notification_preference \
         WHERE app_user_id = $1), true)"
    );
    sqlx::query_scalar(&sql)
        .bind(app_user_id)
        .fetch_one(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)
}

/// Insère une notification in-app pour un utilisateur. Retourne son id (à
/// passer à `JobDispatcher::enqueue_push_notification` après commit), ou
/// `None` si le destinataire a désactivé la catégorie du `kind` via
/// `user_notification_preference` (#6258) — l'appelant ne doit alors rien
/// enfiler.
pub(crate) async fn notify_user(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    app_user_id: Uuid,
    kind: &str,
    title: &str,
    data: serde_json::Value,
) -> Result<Option<Uuid>, AppError> {
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(app_user_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if let Some(category) = preference_category(kind) {
        if !category_enabled(tx, app_user_id, category).await? {
            return Ok(None);
        }
    }

    let row = sqlx::query(
        "INSERT INTO notification \
         (app_user_id, kind, title, body_ciphertext, body_key_ref, data) \
         VALUES ($1, $2, $3, '\\x00'::bytea, 'stub', $4) \
         RETURNING id",
    )
    .bind(app_user_id)
    .bind(kind)
    .bind(title)
    .bind(data)
    .fetch_one(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    Ok(Some(row.try_get("id").map_err(|_| AppError::Internal)?))
}

/// Résout l'`app_user_id` d'un compte patient (valeur DB) puis notifie.
/// Retourne `None` si le compte n'existe plus (pas d'erreur : la commande
/// reste valide).
pub(crate) async fn notify_patient_account(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_account_id: Uuid,
    kind: &str,
    title: &str,
    data: serde_json::Value,
) -> Result<Option<(Uuid, Uuid)>, AppError> {
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(patient_account_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let row = sqlx::query("SELECT app_user_id FROM patient_account WHERE id = $1")
        .bind(patient_account_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let Some(row) = row else { return Ok(None) };
    let app_user_id: Uuid = row.try_get("app_user_id").map_err(|_| AppError::Internal)?;
    let Some(notification_id) = notify_user(tx, app_user_id, kind, title, data).await? else {
        return Ok(None);
    };
    Ok(Some((app_user_id, notification_id)))
}

/// Notifie tous les membres actifs d'une pharmacie (staff). Le GUC pharmacie
/// est posé sur la valeur passée (déjà validée par l'appelant : tenant du JWT
/// ou pharmacie destinataire vérifiée en DB).
pub(crate) async fn notify_pharmacy_staff(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    pharmacy_id: Uuid,
    kind: &str,
    title: &str,
    data: serde_json::Value,
) -> Result<Vec<(Uuid, Uuid)>, AppError> {
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(pharmacy_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let rows =
        sqlx::query("SELECT user_id FROM pharmacy_membership WHERE pharmacy_id = $1 AND active")
            .bind(pharmacy_id)
            .fetch_all(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
        if let Some(notification_id) = notify_user(tx, user_id, kind, title, data.clone()).await? {
            out.push((user_id, notification_id));
        }
    }
    Ok(out)
}

/// Notifie tous les membres actifs d'un tenant infirmier (offre de visite,
/// changement de statut). Clone de `notify_pharmacy_staff`. Le GUC nurse est
/// posé sur la valeur passée (déjà validée par l'appelant).
pub(crate) async fn notify_nurse_staff(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    nurse_id: Uuid,
    kind: &str,
    title: &str,
    data: serde_json::Value,
) -> Result<Vec<(Uuid, Uuid)>, AppError> {
    sqlx::query("SELECT set_config('app.current_nurse_id', $1, true)")
        .bind(nurse_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let rows = sqlx::query("SELECT user_id FROM nurse_membership WHERE nurse_id = $1 AND active")
        .bind(nurse_id)
        .fetch_all(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
        if let Some(notification_id) = notify_user(tx, user_id, kind, title, data.clone()).await? {
            out.push((user_id, notification_id));
        }
    }
    Ok(out)
}

/// Notifie les membres actifs d'un cabinet dont le `role` figure dans
/// `roles` (#6262 : devis signé → praticien + secrétariat uniquement, pas
/// tout le staff comme `notify_pharmacy_staff`/`notify_nurse_staff`). Le GUC
/// cabinet est posé sur la valeur passée (déjà validée par l'appelant :
/// tenant du JWT ou cabinet résolu en DB).
pub(crate) async fn notify_cabinet_staff(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    roles: &[&str],
    kind: &str,
    title: &str,
    data: serde_json::Value,
) -> Result<Vec<(Uuid, Uuid)>, AppError> {
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let rows = sqlx::query(
        "SELECT user_id FROM cabinet_membership \
         WHERE cabinet_id = $1 AND active AND role = ANY($2)",
    )
    .bind(cabinet_id)
    .bind(roles)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
        if let Some(notification_id) = notify_user(tx, user_id, kind, title, data.clone()).await? {
            out.push((user_id, notification_id));
        }
    }
    Ok(out)
}

/// Enveloppe WS `order_status_changed` — zéro PII. Générique (réutilisée par le
/// domaine infirmier avec l'id de la demande de visite comme `order_id`).
pub(crate) fn order_event(channel: &str, order_id: Uuid, status: &str) -> String {
    serde_json::json!({
        "channel": channel,
        "event": "order_status_changed",
        "data": { "order_id": order_id, "status": status }
    })
    .to_string()
}
