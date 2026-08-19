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

/// Insère une notification in-app pour un utilisateur. Retourne son id
/// (à passer à `JobDispatcher::enqueue_push_notification` après commit).
pub(crate) async fn notify_user(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    app_user_id: Uuid,
    kind: &str,
    title: &str,
    data: serde_json::Value,
) -> Result<Uuid, AppError> {
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(app_user_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
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
    row.try_get("id").map_err(|_| AppError::Internal)
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
    let notification_id = notify_user(tx, app_user_id, kind, title, data).await?;
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
        let notification_id = notify_user(tx, user_id, kind, title, data.clone()).await?;
        out.push((user_id, notification_id));
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
        let notification_id = notify_user(tx, user_id, kind, title, data.clone()).await?;
        out.push((user_id, notification_id));
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
