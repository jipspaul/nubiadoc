//! Isolation multi-tenant : exécute du code dans une transaction RLS-scoped.

use thiserror::Error;
use uuid::Uuid;

/// Erreur liée à la gestion du contexte tenant.
#[derive(Debug, Error)]
pub enum TenancyError {
    #[error("erreur de base de données : {0}")]
    Db(#[from] sqlx::Error),
}

/// Exécute `f` dans une transaction PostgreSQL avec le contexte tenant positionné.
///
/// Positionne `app.current_cabinet_id` via `SET LOCAL` (paramétré) avant d'appeler
/// `f`. Les policies RLS du rôle `nubia_app` filtrent sur ce réglage.
/// Le `cabinet_id` doit provenir du JWT vérifié, jamais d'un body/query client.
pub async fn with_tenant<F, Fut, T>(
    pool: &sqlx::PgPool,
    cabinet_id: Uuid,
    f: F,
) -> Result<T, TenancyError>
where
    F: FnOnce(sqlx::Transaction<'static, sqlx::Postgres>) -> Fut,
    Fut: std::future::Future<Output = Result<T, TenancyError>>,
{
    let mut tx = pool.begin().await?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await?;
    f(tx).await
}
