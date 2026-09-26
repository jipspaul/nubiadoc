//! Garde partagée : `axum` implémente `FromRequest` pour `Option<Json<T>>` en
//! avalant l'erreur de désérialisation et en rendant `None` — le
//! `#[serde(deny_unknown_fields)]` posé sur `T` n'a alors jamais l'occasion de
//! remonter un `422` : un corps mal formé (champ inconnu, mauvais type) est
//! silencieusement traité comme un corps absent, et la donnée envoyée par
//! l'appelant disparaît sans trace derrière un `200` (#6999).
//!
//! À utiliser à la place de `body: Option<Json<T>>` sur tout endpoint dont le
//! corps est optionnel mais dont la structure porte `deny_unknown_fields` :
//! extraire `body: axum::body::Bytes` puis appeler [`parse_optional_json_body`]
//! (ou [`parse_optional_json_body_presence`] si le handler distingue corps
//! absent et corps présent avec des valeurs par défaut).

use serde::de::DeserializeOwned;

use crate::auth::AppError;

fn deserialize_strict<T: DeserializeOwned>(bytes: &[u8]) -> Result<T, AppError> {
    serde_json::from_slice(bytes).map_err(|e| {
        if e.is_data() {
            AppError::ValidationError
        } else {
            AppError::BadRequest
        }
    })
}

/// Désérialise un corps JSON optionnel : absent/vide → `T::default()`, sinon
/// désérialisation stricte, avec le même verdict qu'un `Json<T>` non-optionnel :
/// JSON syntaxiquement invalide → `400`, champ inconnu (`deny_unknown_fields`)
/// ou mauvais type → `422`.
pub fn parse_optional_json_body<T: DeserializeOwned + Default>(
    bytes: &[u8],
) -> Result<T, AppError> {
    if bytes.is_empty() {
        return Ok(T::default());
    }
    deserialize_strict(bytes)
}

/// Comme [`parse_optional_json_body`], mais pour les handlers où l'absence de
/// corps a une sémantique distincte d'un corps présent portant des valeurs
/// par défaut (ex. `scope: Vec<String>` vide explicite vs. non fourni) :
/// absent/vide → `None`, sinon `Some(T)` désérialisé strictement.
pub fn parse_optional_json_body_presence<T: DeserializeOwned>(
    bytes: &[u8],
) -> Result<Option<T>, AppError> {
    if bytes.is_empty() {
        return Ok(None);
    }
    deserialize_strict(bytes).map(Some)
}
