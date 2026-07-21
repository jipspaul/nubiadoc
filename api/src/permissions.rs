//! Extracteur `ProBillingClaims` (#4081) — première consommation de
//! `cabinet_membership.permissions` (jsonb, migration 0002) par le
//! middleware d'autorisation. Jusqu'ici la colonne existait mais n'était lue
//! par aucun handler — l'autorisation reposait uniquement sur le rôle
//! grossier (`role` du JWT).
//!
//! Format jsonb attendu (documenté ici, faute d'un format préexistant) :
//! `{"billing": false}` retire explicitement l'accès à une route sensible
//! malgré un rôle normalement autorisé (ex. `secretary`, qui a accès à la
//! facturation par défaut). Absence de la clé, valeur `true`, ou
//! `permissions = {}` (valeur par défaut de la colonne pour toute ligne
//! existante) → comportement INCHANGÉ, autorisé par le rôle grossier.
//!
//! Sémantique volontairement **default-allow, sauf refus explicite** :
//! un default-deny casserait tous les memberships existants (`permissions`
//! vaut `'{}'` par défaut depuis la migration 0002 — aucune ligne actuelle
//! n'a de clé `billing`). Extensible à d'autres clés (`patients`,
//! `messaging`, ...) en ajoutant `key: &str` aux appelants de
//! `check_permission`, sans changer ce contrat.
//!
//! Consommé aujourd'hui par une seule route sensible
//! (`GET /v1/cabinet/quotes`, facturation) — l'issue #4081 demande
//! explicitement "au moins une route", pas une réécriture de l'autorisation
//! existante sur l'ensemble des ~30 routes `ProSecretaryPlusClaims`.

use async_trait::async_trait;
use axum::extract::FromRequestParts;
use axum::http::request::Parts;
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::Deserialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{auth::AppError, AppState};

/// Forme interne : extrait `kind` pour le double-décodage (même pattern que
/// `auth::KindClaims`, dupliqué ici — `auth/mod.rs` est déjà au-dessus du
/// plafond de taille CLAUDE.md, pas d'ajout dessus pour ce petit extracteur).
#[derive(Deserialize)]
struct KindClaims {
    kind: String,
}

/// Claims JWT pro (secretary/practitioner/admin) + vérification de
/// `cabinet_membership.permissions->>'billing'` (#4081). Même contrat que
/// `auth::ProSecretaryPlusClaims` (tout rôle pro accepté), avec un refus
/// additionnel possible si `permissions.billing = false`.
#[derive(Debug, Deserialize)]
pub(crate) struct ProBillingClaims {
    pub(crate) sub: Uuid,
    pub(crate) cabinet_id: Uuid,
    #[allow(dead_code)] // exposé pour un usage futur (cloisonnement clinique éventuel)
    pub(crate) role: String,
}

#[async_trait]
impl FromRequestParts<AppState> for ProBillingClaims {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or(AppError::Unauthorized)?;

        let token = auth.strip_prefix("Bearer ").ok_or(AppError::Unauthorized)?;

        let key = DecodingKey::from_secret(state.jwt_secret.as_bytes());
        let mut validation = Validation::default();
        validation.validate_exp = true;

        // Première passe : extrait `kind` pour renvoyer 403 (pas 401) si le
        // token est valide mais n'appartient pas à un pro (ex. token patient).
        let basic = decode::<KindClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if basic.kind != "pro" {
            return Err(AppError::Forbidden);
        }

        // Deuxième passe : décode les champs pro obligatoires.
        let claims = decode::<ProBillingClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if !membership_allows(state, claims.cabinet_id, claims.sub, "billing").await? {
            return Err(AppError::Forbidden);
        }

        Ok(claims)
    }
}

/// `false` UNIQUEMENT si `cabinet_membership.permissions->>key = false`
/// (littéral JSON) pour ce `(cabinet_id, user_id)` — absence de ligne, de
/// clé, ou valeur autre que `false` → `true` (default-allow, cf. doc de
/// module). RLS scopée via `app.current_cabinet_id` (le `cabinet_id` du
/// JWT, comme tout handler qui positionne ce GUC depuis les claims).
async fn membership_allows(
    state: &AppState,
    cabinet_id: Uuid,
    user_id: Uuid,
    key: &str,
) -> Result<bool, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT permissions FROM cabinet_membership WHERE cabinet_id = $1 AND user_id = $2",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        return Ok(true);
    };
    let permissions: serde_json::Value =
        row.try_get("permissions").map_err(|_| AppError::Internal)?;

    Ok(permissions.get(key).and_then(serde_json::Value::as_bool) != Some(false))
}
