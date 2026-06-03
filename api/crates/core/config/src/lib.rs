//! Configuration applicative chargée depuis les variables d'environnement.

use thiserror::Error;

/// Environnement d'exécution.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Env {
    Dev,
    Staging,
    Prod,
}

/// Configuration applicative.
///
/// `app_database_url` = rôle `nubia_app` (runtime + RLS active).
/// `database_url` = rôle `nubia_owner` réservé aux migrations, jamais au runtime.
#[derive(Debug, Clone)]
pub struct AppConfig {
    /// URL runtime (rôle nubia_app, RLS active). Jamais l'URL owner.
    pub app_database_url: String,
    /// URL DDL migrations (rôle nubia_owner, hors runtime).
    pub database_url: String,
    pub redis_url: String,
    /// Clé de signature JWT — ne jamais émettre en log.
    pub jwt_secret: String,
    /// Identifiant de clé KMS (Scaleway ou locale POC).
    pub kms_key_id: String,
    pub env: Env,
}

/// Erreur de lecture de configuration.
#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("variable d'environnement manquante : {0}")]
    MissingVar(String),
}

impl AppConfig {
    /// Charge la configuration depuis les variables d'environnement du processus.
    ///
    /// Variables requises : `APP_DATABASE_URL`, `DATABASE_URL`, `REDIS_URL`,
    /// `JWT_SECRET`, `KMS_KEY_ID`.
    /// Variable optionnelle : `APP_ENV` (`dev`|`staging`|`prod`, défaut `dev`).
    pub fn from_env() -> Result<Self, ConfigError> {
        Self::load(|name| std::env::var(name).ok())
    }

    fn load(get: impl Fn(&str) -> Option<String>) -> Result<Self, ConfigError> {
        let required = |name: &str| -> Result<String, ConfigError> {
            get(name).ok_or_else(|| ConfigError::MissingVar(name.to_string()))
        };

        let env = match get("APP_ENV").unwrap_or_default().as_str() {
            "staging" => Env::Staging,
            "prod" | "production" => Env::Prod,
            _ => Env::Dev,
        };

        Ok(AppConfig {
            app_database_url: required("APP_DATABASE_URL")?,
            database_url: required("DATABASE_URL")?,
            redis_url: required("REDIS_URL")?,
            jwt_secret: required("JWT_SECRET")?,
            kms_key_id: required("KMS_KEY_ID")?,
            env,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_from_env_missing_var_returns_error() {
        let result = AppConfig::load(|_| None);
        assert!(
            matches!(result, Err(ConfigError::MissingVar(_))),
            "from_env doit retourner MissingVar quand aucune variable n'est définie"
        );
    }

    #[test]
    fn test_load_all_vars_staging() {
        let result = AppConfig::load(|name| match name {
            "APP_DATABASE_URL" => Some("postgres://nubia_app@localhost/nubia".into()),
            "DATABASE_URL" => Some("postgres://nubia_owner@localhost/nubia".into()),
            "REDIS_URL" => Some("redis://localhost:6379".into()),
            "JWT_SECRET" => Some("secret-jwt".into()),
            "KMS_KEY_ID" => Some("kms-poc-key".into()),
            "APP_ENV" => Some("staging".into()),
            _ => None,
        });
        let config = result.expect("load doit réussir avec toutes les vars");
        assert_eq!(config.env, Env::Staging);
        assert_eq!(config.redis_url, "redis://localhost:6379");
    }
}
