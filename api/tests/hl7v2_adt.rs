//! Lot B8 (#3927) — mapping ADT → référentiel patient, testé au niveau
//! `hl7v2::adt::handle` (le transport MLLP/mTLS est couvert par
//! `hl7v2_e2e.rs`). Nécessite `KMS_MASTER_KEY` (posée par le test) et une
//! base migrée (`db_available()`, même convention que les tests interop).

use base64::engine::{general_purpose::STANDARD, Engine};
use sqlx::PgPool;
use uuid::Uuid;

use integrations_hl7v2::parser::parse;
use nubia_api::hl7v2::adt;

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

fn ensure_kms_env() {
    if std::env::var("KMS_MASTER_KEY").is_err() {
        std::env::set_var("KMS_MASTER_KEY", STANDARD.encode([7u8; 32]));
    }
}

/// ADT^`trigger` minimal : PID-3 = INS (autorité INS-NIR) + une répétition
/// non-INS pour vérifier la sélection par autorité ; PID-5/7 = identité.
fn build_adt(trigger: &str, ins: &str, family: &str, given: &str, birth: &str) -> String {
    format!(
        "MSH|^~\\&|SIH|EMETTEUR|NUBIA|DEST|20260905120000||ADT^{trigger}|MSG-{trigger}-1|P|2.5\r\
         PID|1||LOCAL123^^^SIH-LOCAL~{ins}^^^INS-NIR||{family}^{given}||{birth}|\r"
    )
}

async fn insert_cabinet(db: &PgPool) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet ADT {cabinet_id}"))
        .execute(db)
        .await
        .unwrap();
    cabinet_id
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid) {
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
}

/// A28 crée le patient (INS chiffré, jamais en clair en base), A31 met à
/// jour la démographie du même patient (résolution par INS), sans doublon.
#[tokio::test]
async fn adt_a28_creates_then_a31_updates_same_patient() {
    if !db_available() {
        return;
    }
    ensure_kms_env();
    let owner = owner_pool().await;
    let app = app_pool().await;
    let cabinet_id = insert_cabinet(&owner).await;
    let ins = "175086411234567";

    let a28 = parse(&build_adt("A28", ins, "DUPONT", "Jean", "19750815")).unwrap();
    adt::handle(&app, cabinet_id, &a28, "ADT^A28")
        .await
        .unwrap();

    let (count, first_name, ciphertext): (i64, String, Vec<u8>) = sqlx::query_as(
        "SELECT count(*) OVER (), first_name, ins_ciphertext FROM patient \
         WHERE cabinet_id = $1 LIMIT 1",
    )
    .bind(cabinet_id)
    .fetch_one(&owner)
    .await
    .unwrap();
    assert_eq!(count, 1);
    assert_eq!(first_name, "Jean");
    assert!(
        !ciphertext.windows(ins.len()).any(|w| w == ins.as_bytes()),
        "l'INS ne doit jamais apparaître en clair dans le ciphertext"
    );

    // A31 : changement de prénom, même INS → même ligne, pas de doublon.
    let a31 = parse(&build_adt("A31", ins, "DUPONT", "Jean-Marie", "19750815")).unwrap();
    adt::handle(&app, cabinet_id, &a31, "ADT^A31")
        .await
        .unwrap();

    let (count2, first_name2): (i64, String) = sqlx::query_as(
        "SELECT count(*) OVER (), first_name FROM patient WHERE cabinet_id = $1 LIMIT 1",
    )
    .bind(cabinet_id)
    .fetch_one(&owner)
    .await
    .unwrap();
    assert_eq!(count2, 1, "A31 ne doit pas créer de doublon");
    assert_eq!(first_name2, "Jean-Marie");

    cleanup(&owner, cabinet_id).await;
}

/// A31 sur un INS jamais vu → erreur explicite (le SIH doit envoyer un A28
/// d'abord) ; A28 rejoué (même INS) reste idempotent — toujours 1 patient.
#[tokio::test]
async fn adt_a31_unknown_ins_fails_and_a28_is_idempotent() {
    if !db_available() {
        return;
    }
    ensure_kms_env();
    let owner = owner_pool().await;
    let app = app_pool().await;
    let cabinet_id = insert_cabinet(&owner).await;
    let ins = "275126522345678";

    let a31 = parse(&build_adt("A31", ins, "MARTIN", "Sophie", "19751226")).unwrap();
    let err = adt::handle(&app, cabinet_id, &a31, "ADT^A31").await;
    assert!(err.is_err(), "A31 sans A28 préalable doit échouer");

    let a28 = parse(&build_adt("A28", ins, "MARTIN", "Sophie", "19751226")).unwrap();
    adt::handle(&app, cabinet_id, &a28, "ADT^A28")
        .await
        .unwrap();
    adt::handle(&app, cabinet_id, &a28, "ADT^A28")
        .await
        .unwrap();

    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_eq!(count, 1, "A28 rejoué ne doit pas créer de doublon");

    cleanup(&owner, cabinet_id).await;
}

/// PID sans répétition INS-NIR, ou INS mal formé → rejet explicite.
#[tokio::test]
async fn adt_missing_or_malformed_ins_is_rejected() {
    if !db_available() {
        return;
    }
    ensure_kms_env();
    let app = app_pool().await;
    let owner = owner_pool().await;
    let cabinet_id = insert_cabinet(&owner).await;

    let no_ins = parse(
        "MSH|^~\\&|SIH|EMETTEUR|NUBIA|DEST|20260905120000||ADT^A28|MSG-NOINS|P|2.5\r\
         PID|1||LOCAL123^^^SIH-LOCAL||DUPONT^Jean||19750815|\r",
    )
    .unwrap();
    assert!(adt::handle(&app, cabinet_id, &no_ins, "ADT^A28")
        .await
        .is_err());

    let bad_ins = parse(&build_adt("A28", "12AB", "DUPONT", "Jean", "19750815")).unwrap();
    assert!(adt::handle(&app, cabinet_id, &bad_ins, "ADT^A28")
        .await
        .is_err());

    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_eq!(
        count, 0,
        "aucun patient ne doit être créé sur un PID rejeté"
    );

    cleanup(&owner, cabinet_id).await;
}
