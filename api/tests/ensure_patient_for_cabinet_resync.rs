//! Tests d'intégration : fonction SQL `ensure_patient_for_cabinet` (0123/0155).
//!
//! Régression #3895 : un patient réservant AVANT d'avoir complété son profil
//! (patient_account.first_name/last_name encore vides à l'inscription)
//! produisait une fiche `patient` cabinet définitivement anonyme — le nom
//! n'était jamais re-synchronisé, même après que le patient renseigne son nom.

use sqlx::{PgPool, Row};
use uuid::Uuid;

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn owner_pool() -> PgPool {
    let url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_owner@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

#[tokio::test]
async fn ensure_patient_for_cabinet_resyncs_name_after_account_completed() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let app_db = app_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("ensure-patient-resync+{}@nubia.test", user_id))
    .execute(&owner)
    .await
    .unwrap();

    // Profil encore incomplet à l'inscription (comme auth/register.rs : '', '').
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, '', '')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&owner)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet EnsurePatientResync {}", cabinet_id))
        .execute(&owner)
        .await
        .unwrap();

    // 1er appel (réservation avant profil complété) : fiche cabinet créée avec un nom vide.
    let patient_id: Uuid = sqlx::query_scalar("SELECT ensure_patient_for_cabinet($1, $2)")
        .bind(account_id)
        .bind(cabinet_id)
        .fetch_one(&app_db)
        .await
        .unwrap();

    let row = sqlx::query("SELECT first_name, last_name FROM patient WHERE id = $1")
        .bind(patient_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    let first_name: String = row.try_get("first_name").unwrap();
    let last_name: String = row.try_get("last_name").unwrap();
    assert_eq!(first_name, "", "nom vide au 1er appel (profil incomplet)");
    assert_eq!(last_name, "");

    // Le patient complète son profil (équivalent PATCH /v1/account).
    sqlx::query(
        "UPDATE patient_account SET first_name = 'Alice', last_name = 'Dupont' WHERE id = $1",
    )
    .bind(account_id)
    .execute(&owner)
    .await
    .unwrap();

    // 2e appel (ex. 2e réservation) : même fiche (get-or-create), mais le nom
    // doit désormais être resynchronisé depuis patient_account.
    let patient_id_2: Uuid = sqlx::query_scalar("SELECT ensure_patient_for_cabinet($1, $2)")
        .bind(account_id)
        .bind(cabinet_id)
        .fetch_one(&app_db)
        .await
        .unwrap();
    assert_eq!(
        patient_id_2, patient_id,
        "get-or-create doit retourner la MÊME fiche, pas en créer une 2e"
    );

    let row2 = sqlx::query("SELECT first_name, last_name FROM patient WHERE id = $1")
        .bind(patient_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    let first_name_2: String = row2.try_get("first_name").unwrap();
    let last_name_2: String = row2.try_get("last_name").unwrap();
    assert_eq!(
        first_name_2, "Alice",
        "le nom doit être resynchronisé depuis patient_account après complétion du profil"
    );
    assert_eq!(last_name_2, "Dupont");

    // Nettoyage.
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&owner)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&owner)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&owner)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&owner)
        .await
        .ok();
}
