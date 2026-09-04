//! `ObjectStorage` persistant — Postgres, #6453.
//!
//! `InMemoryObjectStorage` (câblé en dur en production dans `build_router`)
//! ne survit à aucun redémarrage du process : chaque redéploiement
//! (`infra/deploy/deploy.sh` fait `podman rm -f nubia-api` puis `podman run`,
//! sans volume monté pour l'API — contrairement à `nubia-pg`) repartait donc
//! avec un coffre-fort vide, transformant toute ordonnance signée en 404
//! définitif dès le déploiement suivant. Postgres (`nubia_pg`, volume
//! persistant) est le seul composant réellement durable de cette topologie :
//! cette implémentation y stocke les objets (table `object_storage_blob`,
//! migration `db/migrations/0250`) au lieu du process.

use async_trait::async_trait;
use sqlx::{PgPool, Row};

use crate::ObjectStorage;

pub struct PostgresObjectStorage {
    pool: PgPool,
}

impl PostgresObjectStorage {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl ObjectStorage for PostgresObjectStorage {
    async fn upload(&self, key: &str, content_type: &str, bytes: Vec<u8>) -> Result<(), String> {
        sqlx::query(
            "INSERT INTO object_storage_blob (key, content_type, bytes) \
             VALUES ($1, $2, $3) \
             ON CONFLICT (key) DO UPDATE SET content_type = EXCLUDED.content_type, \
             bytes = EXCLUDED.bytes",
        )
        .bind(key)
        .bind(content_type)
        .bind(bytes)
        .execute(&self.pool)
        .await
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    async fn download(&self, key: &str) -> Option<(String, Vec<u8>)> {
        let row = sqlx::query("SELECT content_type, bytes FROM object_storage_blob WHERE key = $1")
            .bind(key)
            .fetch_optional(&self.pool)
            .await
            .ok()??;
        let content_type: String = row.try_get("content_type").ok()?;
        let bytes: Vec<u8> = row.try_get("bytes").ok()?;
        Some((content_type, bytes))
    }
}
