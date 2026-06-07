//! Handler `POST /v1/auth/refresh`.

use axum::extract::{Json, State};
use chrono::Utc;
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::Deserialize;
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::AppState;

use super::{AppError, LoginResponse, PatientClaims, ProClaims, ProRegisterClaims};

/// Corps de la requête `POST /v1/auth/refresh`.
#[derive(Deserialize)]
pub struct RefreshBody {
    refresh_token: String,
}

/// `POST /v1/auth/refresh` — rotation du refresh token.
///
/// Échange un refresh token valide contre un nouveau access token + nouveau refresh token.
/// L'ancien token est révoqué atomiquement dans la même transaction (rotation).
/// Token inconnu ou expiré → `401`.
/// Token révoqué (replay) → `401` + révocation de toute la chaîne de l'utilisateur.
pub async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshBody>,
) -> Result<Json<LoginResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // refresh_token a FORCE RLS token_user_select (app.current_user_id requis).
    // On utilise refresh_token_owner() SECURITY DEFINER (migration 0066) pour
    // bootstrapper le user_id sans GUC, comme dans logout.rs.
    let token_hash_row =
        sqlx::query("SELECT refresh_token_owner(encode(digest($1, 'sha256'), 'hex')) AS owner_id")
            .bind(&body.refresh_token)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    let user_id: Uuid = token_hash_row
        .try_get::<Option<Uuid>, _>("owner_id")
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::Unauthenticated)?;

    // Pose le GUC pour satisfaire token_user_select sur la lecture complète.
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Cherche le token sans filtrer sur revoked_at/expires_at pour distinguer les cas.
    let row = sqlx::query(
        "SELECT app_user_id, revoked_at, expires_at FROM refresh_token \
         WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
    )
    .bind(&body.refresh_token)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::Unauthenticated)?;
    let revoked_at: Option<chrono::DateTime<Utc>> =
        row.try_get("revoked_at").map_err(|_| AppError::Internal)?;
    let expires_at: chrono::DateTime<Utc> =
        row.try_get("expires_at").map_err(|_| AppError::Internal)?;

    if revoked_at.is_some() {
        // Replay détecté : révoque toute la chaîne active (vol de token présumé).
        sqlx::query(
            "UPDATE refresh_token SET revoked_at = now() \
             WHERE app_user_id = $1 AND revoked_at IS NULL",
        )
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Err(AppError::Unauthenticated);
    }

    if expires_at <= Utc::now() {
        tx.rollback().await.ok();
        return Err(AppError::Unauthenticated);
    }

    // Token valide : révoque l'ancien, émet le nouveau.
    sqlx::query(
        "UPDATE refresh_token SET revoked_at = now() \
         WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
    )
    .bind(&body.refresh_token)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let user_row = sqlx::query("SELECT kind FROM app_user WHERE id = $1")
        .bind(user_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let kind: String = user_row.try_get("kind").map_err(|_| AppError::Internal)?;

    let new_raw_token = Uuid::new_v4().to_string();
    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&new_raw_token)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    const EXPIRES_IN: u64 = 900;
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + EXPIRES_IN;

    let access_token = if kind == "patient" {
        // patient_account FORCE RLS : account_auth_select exige app.current_user_id.
        // Le GUC est déjà posé dans tx, mais on est sorti de la tx au commit().
        // On ouvre une nouvelle tx courte pour poser le GUC et lire patient_account.
        let mut tx2 = state.db.begin().await.map_err(|_| AppError::Internal)?;
        // patient_account a FORCE RLS avec account_auth_select (migration 0069).
        // La policy utilise app.current_login_user_id (GUC dédié, pas current_user_id).
        sqlx::query("SELECT set_config('app.current_login_user_id', $1, true)")
            .bind(user_id.to_string())
            .execute(&mut *tx2)
            .await
            .map_err(|_| AppError::Internal)?;
        let acct_row = sqlx::query("SELECT id FROM patient_account WHERE app_user_id = $1")
            .bind(user_id)
            .fetch_optional(&mut *tx2)
            .await
            .map_err(|_| AppError::Internal)?;
        tx2.commit().await.map_err(|_| AppError::Internal)?;
        let account_id: Uuid = acct_row
            .map(|r| r.try_get("id"))
            .transpose()
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::Internal)?;
        encode(
            &Header::default(),
            &PatientClaims {
                sub: user_id,
                kind: "patient".to_string(),
                account_id,
                exp,
            },
            &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
        )
        .map_err(|_| AppError::Internal)?
    } else {
        // Re-resolve cabinet_id + role from cabinet_membership (même logique que R1 login).
        // user_active_membership() est SECURITY DEFINER (migration 0083), contourne la RLS
        // cabinet-scoped pour bootstrapper le tenant sans GUC préalable.
        let mut tx2 = state.db.begin().await.map_err(|_| AppError::Internal)?;
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(user_id.to_string())
            .execute(&mut *tx2)
            .await
            .map_err(|_| AppError::Internal)?;
        let membership_row = sqlx::query("SELECT cabinet_id, role FROM user_active_membership($1)")
            .bind(user_id)
            .fetch_optional(&mut *tx2)
            .await
            .map_err(|_| AppError::Internal)?;
        tx2.commit().await.map_err(|_| AppError::Internal)?;

        match membership_row {
            Some(r) => {
                let cabinet_id: Uuid = r.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
                let role: String = r.try_get("role").map_err(|_| AppError::Internal)?;
                encode(
                    &Header::default(),
                    &ProRegisterClaims {
                        sub: user_id,
                        kind: "pro".to_string(),
                        cabinet_id,
                        role,
                        exp,
                    },
                    &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
                )
                .map_err(|_| AppError::Internal)?
            }
            None => encode(
                &Header::default(),
                &ProClaims {
                    sub: user_id,
                    kind: "pro".to_string(),
                    exp,
                },
                &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
            )
            .map_err(|_| AppError::Internal)?,
        }
    };

    Ok(Json(LoginResponse {
        access_token,
        refresh_token: new_raw_token,
        token_type: "Bearer".to_string(),
        expires_in: EXPIRES_IN,
    }))
}
