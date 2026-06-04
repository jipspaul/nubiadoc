//! Handler `POST /v1/auth/password/forgot`.

use axum::{extract::State, Json};
use serde::Deserialize;
use serde_json::{json, Value};
use uuid::Uuid;

use crate::AppState;

/// Corps de la requête `POST /v1/auth/password/forgot`.
#[derive(Deserialize)]
pub struct ForgotPasswordBody {
    email: String,
}

/// `POST /v1/auth/password/forgot` — déclenche le reset de mot de passe.
///
/// Réponse toujours identique (200 + message neutre) que l'email existe ou non
/// (anti-énumération §1.8). Si l'email est connu, génère un token UUID, le stocke
/// hashé (SHA-256 via pgcrypto) avec une expiration d'une heure, puis notifie via
/// le mailer.
pub async fn forgot_password(
    State(state): State<AppState>,
    Json(body): Json<ForgotPasswordBody>,
) -> Json<Value> {
    let token = Uuid::new_v4().to_string();

    let result = sqlx::query(
        r#"
        UPDATE app_user
        SET
            password_reset_token      = encode(digest($2, 'sha256'), 'hex'),
            password_reset_expires_at = now() + interval '1 hour'
        WHERE email = $1
        "#,
    )
    .bind(&body.email)
    .bind(&token)
    .execute(&state.db)
    .await;

    match result {
        Ok(outcome) if outcome.rows_affected() > 0 => {
            state.mailer.send_password_reset(&body.email, &token);
        }
        Ok(_) => {}
        Err(e) => {
            tracing::error!(error = ?e, "forgot_password: db update failed");
        }
    }

    Json(json!({"message": "Si un compte existe, un email a été envoyé."}))
}
