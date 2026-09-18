//! Chemin d'écriture unique des fichiers téléversés par un utilisateur
//! (coffre-fort patient, carte mutuelle, document versé au dossier par le
//! cabinet) — #7135 / #6894 / #6802.
//!
//! Quoi : génère la `storage_key` d'un upload utilisateur ET écrit les
//! octets dans l'`ObjectStorage` injecté (`PostgresObjectStorage` en prod,
//! cf. `build_router`), en une seule fonction. La clé n'est retournée que si
//! l'objet a réellement été écrit — impossible de persister une ligne
//! `document` qui référence une clé fantôme.
//!
//! Pourquoi : les trois endpoints d'upload inventaient chacun un
//! `storage_key = Uuid::new_v4()` puis inséraient la ligne `document` sans
//! jamais appeler `ObjectStorage::upload`. Le `201` était rendu avec la
//! bonne taille et le bon sha256… et `GET <download_url>` répondait `404`
//! (objet jamais uploadé) : perte silencieuse et définitive du fichier. Seuls
//! les PDF générés serveur (`prescriptions.rs`, `billing.rs`,
//! `implant_passport.rs`) passaient par `.upload()`. Centraliser le chemin
//! d'écriture empêche qu'un futur endpoint d'upload reparte sur le stub.
//!
//! Ordre d'appel : à invoquer APRÈS toutes les gardes (validation, RBAC,
//! scope tenant) et AVANT le `COMMIT` de la transaction qui insère la ligne
//! `document`. Si l'écriture échoue → `500 internal` et la transaction est
//! abandonnée (pas de ligne orpheline). Si le `COMMIT` échoue ensuite, seul
//! un blob orphelin subsiste — inoffensif (clé opaque jamais référencée).
//!
//! Format de clé : `<prefix>/<uuid>` — même convention que
//! `ordonnance/<id>.pdf`, lisible dans les logs et l'Object Storage, et
//! transportée telle quelle par `LocalStorageSigner` (`/v1/storage/local/*key`)
//! comme par `ScalewayStorageSigner` (clé S3 avec `/`).

use uuid::Uuid;

use crate::{auth::AppError, ObjectStorage};

/// Préfixe de clé des pièces déposées par le patient dans son coffre-fort
/// (`POST /v1/documents`).
pub const PREFIX_PATIENT_VAULT: &str = "coffre";
/// Préfixe de clé des scans de carte mutuelle (`POST /v1/account/coverage/card`).
pub const PREFIX_COVERAGE_CARD: &str = "carte-mutuelle";
/// Préfixe de clé des documents versés au dossier par le cabinet
/// (`POST /v1/cabinet/patients/:id/documents`).
pub const PREFIX_CABINET_DOCUMENT: &str = "dossier";

/// Écrit `bytes` dans l'`ObjectStorage` sous une clé fraîche `<prefix>/<uuid>`
/// et retourne cette clé. Échec d'écriture → `AppError::Internal` (journalisé,
/// zéro PII : seule la clé et le message d'erreur du backend sont tracés).
pub async fn store_upload(
    storage: &dyn ObjectStorage,
    prefix: &str,
    content_type: &str,
    bytes: Vec<u8>,
) -> Result<String, AppError> {
    let storage_key = format!("{prefix}/{}", Uuid::new_v4());
    let size_bytes = bytes.len();
    storage
        .upload(&storage_key, content_type, bytes)
        .await
        .map_err(|err| {
            tracing::error!(
                storage_key = %storage_key,
                size_bytes,
                error = %err,
                "object storage upload failed — upload refusé (pas de ligne document orpheline)"
            );
            AppError::Internal
        })?;
    Ok(storage_key)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::InMemoryObjectStorage;

    struct FailingStorage;

    #[async_trait::async_trait]
    impl ObjectStorage for FailingStorage {
        async fn upload(&self, _key: &str, _ct: &str, _bytes: Vec<u8>) -> Result<(), String> {
            Err("backend down".to_string())
        }

        async fn download(&self, _key: &str) -> Option<(String, Vec<u8>)> {
            None
        }
    }

    #[tokio::test]
    async fn store_upload_writes_the_bytes_under_the_returned_key() {
        let storage = InMemoryObjectStorage::default();
        let bytes = b"%PDF-1.4 test".to_vec();

        let key = store_upload(
            &storage,
            PREFIX_PATIENT_VAULT,
            "application/pdf",
            bytes.clone(),
        )
        .await
        .unwrap();

        assert!(key.starts_with("coffre/"), "clé préfixée : {key}");
        let (content_type, stored) = storage.download(&key).await.expect("objet écrit");
        assert_eq!(content_type, "application/pdf");
        assert_eq!(stored, bytes);
    }

    #[tokio::test]
    async fn store_upload_returns_internal_when_the_backend_fails() {
        let result =
            store_upload(&FailingStorage, PREFIX_COVERAGE_CARD, "image/png", vec![1]).await;
        assert!(matches!(result, Err(AppError::Internal)));
    }

    #[tokio::test]
    async fn store_upload_generates_a_fresh_key_per_call() {
        let storage = InMemoryObjectStorage::default();
        let a = store_upload(&storage, PREFIX_CABINET_DOCUMENT, "image/png", vec![1])
            .await
            .unwrap();
        let b = store_upload(&storage, PREFIX_CABINET_DOCUMENT, "image/png", vec![2])
            .await
            .unwrap();
        assert_ne!(a, b);
    }
}
