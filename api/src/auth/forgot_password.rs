//! Handler `POST /v1/auth/password/forgot`.

use axum::{
    extract::{rejection::JsonRejection, State},
    http::StatusCode,
    Json,
};
use serde::Deserialize;
use sqlx::Row;
use uuid::Uuid;

use crate::AppState;

/// Corps de la requête `POST /v1/auth/password/forgot`.
#[derive(Deserialize)]
pub struct ForgotPasswordBody {
    email: String,
}

/// `POST /v1/auth/password/forgot` — déclenche le reset de mot de passe.
///
/// Réponse toujours `204` que l'email existe ou non (anti-énumération §1.8).
/// Si l'email est connu, génère un token UUID, le stocke hashé (SHA-256 via pgcrypto)
/// avec une expiration d'une heure, puis notifie via le mailer.
///
/// #3785 : un email inconnu ne doit pas seulement renvoyer la MÊME réponse
/// qu'un email connu, mais faire le MÊME travail — sinon la latence (2e
/// transaction + UPDATE + mailer en plus pour un email connu) devient un
/// canal auxiliaire mesurable qui défait l'anti-énumération malgré le 204
/// constant. On exécute donc systématiquement la 2e transaction + l'UPDATE
/// (sur un id bidon si l'email est inconnu — 0 ligne affectée, même coût
/// d'index lookup) ; seul l'envoi mailer reste conditionnel au résultat réel.
pub async fn forgot_password(
    State(state): State<AppState>,
    body: Result<Json<ForgotPasswordBody>, JsonRejection>,
) -> StatusCode {
    let Json(body) = match body {
        Ok(b) => b,
        Err(_) => return StatusCode::UNPROCESSABLE_ENTITY,
    };
    let token = Uuid::new_v4().to_string();

    // Pose app.current_login_email pour satisfaire user_login_select (migration 0065).
    let mut auth_tx = match state.db.begin().await {
        Ok(tx) => tx,
        Err(_) => return StatusCode::NO_CONTENT,
    };
    if sqlx::query("SELECT set_config('app.current_login_email', $1, true)")
        .bind(&body.email)
        .execute(&mut *auth_tx)
        .await
        .is_err()
    {
        return StatusCode::NO_CONTENT;
    }
    let user_row = sqlx::query("SELECT id FROM app_user WHERE email = $1")
        .bind(&body.email)
        .fetch_optional(&mut *auth_tx)
        .await;
    let _ = auth_tx.rollback().await;

    // Email inconnu → id bidon (ne matchera jamais de ligne réelle) plutôt
    // qu'un retour anticipé : la suite du handler s'exécute à l'identique.
    let (user_id, user_found) = match user_row {
        Ok(Some(r)) => match r.try_get::<Uuid, _>("id") {
            Ok(id) => (id, true),
            Err(_) => (Uuid::new_v4(), false),
        },
        _ => (Uuid::new_v4(), false),
    };

    let mut tx = match state.db.begin().await {
        Ok(tx) => tx,
        Err(_) => return StatusCode::NO_CONTENT,
    };

    if sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .is_err()
    {
        return StatusCode::NO_CONTENT;
    }

    let result = sqlx::query(
        r#"
        UPDATE app_user
        SET
            password_reset_token      = encode(digest($2, 'sha256'), 'hex'),
            password_reset_expires_at = now() + interval '1 hour'
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .bind(&token)
    .execute(&mut *tx)
    .await;

    match (result, tx.commit().await) {
        (Ok(outcome), Ok(())) if user_found && outcome.rows_affected() > 0 => {
            state.mailer.send_password_reset(&body.email, &token);
        }
        (Err(e), _) if user_found => {
            tracing::error!(error = ?e, "forgot_password: db update failed");
        }
        _ => {}
    }

    StatusCode::NO_CONTENT
}
