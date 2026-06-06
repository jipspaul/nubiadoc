//! Handler `POST /v1/auth/password/forgot`.

use axum::{extract::State, http::StatusCode, Json};
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
pub async fn forgot_password(
    State(state): State<AppState>,
    Json(body): Json<ForgotPasswordBody>,
) -> StatusCode {
    let token = Uuid::new_v4().to_string();

    // Récupère l'id via user_auth_select (USING true), puis pose app.current_user_id
    // pour satisfaire user_self_update (FORCE RLS) avant l'UPDATE.
    let user_row = sqlx::query("SELECT id FROM app_user WHERE email = $1")
        .bind(&body.email)
        .fetch_optional(&state.db)
        .await;

    let user_id = match user_row {
        Ok(Some(r)) => match r.try_get::<Uuid, _>("id") {
            Ok(id) => id,
            Err(_) => return StatusCode::NO_CONTENT,
        },
        _ => return StatusCode::NO_CONTENT,
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
        (Ok(outcome), Ok(())) if outcome.rows_affected() > 0 => {
            state.mailer.send_password_reset(&body.email, &token);
        }
        (Err(e), _) => {
            tracing::error!(error = ?e, "forgot_password: db update failed");
        }
        _ => {}
    }

    StatusCode::NO_CONTENT
}
