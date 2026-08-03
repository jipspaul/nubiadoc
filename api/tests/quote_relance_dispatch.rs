//! Tests d'intégration : `dispatch_quote_relances` (#4126) — appelable
//! directement par les tests, même convention que `dispatch_pending_reminders`
//! (#4034).

use nubia_api::dispatch_quote_relances;
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

struct Fixtures {
    cabinet_id: Uuid,
    patient_user_id: Uuid,
    patient_account_id: Uuid,
    quote_id: Uuid,
}

/// `sent_days_ago` : ancienneté simulée de `quote.sent_at`.
async fn insert_fixtures(db: &PgPool, sent_days_ago: i64) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("relance-patient+{patient_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Relance', 'Test')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Relance Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Relance', 'Patient', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, sent_at) \
         VALUES ($1, $2, $3, 'sent', 150.00, 'EUR', now() - make_interval(days => $4::int))",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(sent_days_ago)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        patient_user_id,
        patient_account_id,
        quote_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_relance WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.patient_user_id)
        .execute(db)
        .await
        .ok();
}


async fn count_milestone(db: &PgPool, cabinet_id: Uuid, quote_id: Uuid, milestone: &str) -> i64 {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let c = sqlx::query_scalar(
        "SELECT count(*) FROM quote_relance WHERE quote_id = $1 AND milestone = $2",
    )
    .bind(quote_id)
    .bind(milestone)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    c
}

#[tokio::test]
async fn quote_sent_4_days_ago_gets_j3_relance() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixtures(&owner_db, 4).await;

    dispatch_quote_relances(&app_db).await.unwrap();
    assert_eq!(count_milestone(&owner_db, f.cabinet_id, f.quote_id, "j3").await, 1);
    assert_eq!(count_milestone(&owner_db, f.cabinet_id, f.quote_id, "j7").await, 0);

    let mut tx = owner_db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT milestone FROM quote_relance WHERE quote_id = $1")
        .bind(f.quote_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let milestone: String = row.try_get("milestone").unwrap();
    assert_eq!(milestone, "j3");

    let notif_count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM notification WHERE app_user_id = $1 AND kind = 'quote_relance'",
    )
    .bind(f.patient_user_id)
    .fetch_one(&owner_db)
    .await
    .unwrap();
    assert_eq!(notif_count, 1);

    cleanup_fixtures(&owner_db, &f).await;
}

#[tokio::test]
async fn quote_sent_8_days_ago_gets_both_milestones() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixtures(&owner_db, 8).await;

    dispatch_quote_relances(&app_db).await.unwrap();
    assert_eq!(count_milestone(&owner_db, f.cabinet_id, f.quote_id, "j3").await, 1);
    assert_eq!(count_milestone(&owner_db, f.cabinet_id, f.quote_id, "j7").await, 1);

    let count: i64 = {
        let mut tx = owner_db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let c = sqlx::query_scalar("SELECT count(*) FROM quote_relance WHERE quote_id = $1")
            .bind(f.quote_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
        c
    };
    assert_eq!(count, 2);

    cleanup_fixtures(&owner_db, &f).await;
}

#[tokio::test]
async fn quote_sent_1_day_ago_gets_no_relance() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixtures(&owner_db, 1).await;

    dispatch_quote_relances(&app_db).await.unwrap();
    assert_eq!(count_milestone(&owner_db, f.cabinet_id, f.quote_id, "j3").await, 0);
    assert_eq!(count_milestone(&owner_db, f.cabinet_id, f.quote_id, "j7").await, 0);

    cleanup_fixtures(&owner_db, &f).await;
}

/// #4126 : deux passages successifs du worker sur le même devis ne créent
/// pas de doublon (UNIQUE(quote_id, milestone), ON CONFLICT DO NOTHING).
#[tokio::test]
async fn dispatch_is_idempotent_across_runs() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixtures(&owner_db, 4).await;

    dispatch_quote_relances(&app_db).await.unwrap();
    assert_eq!(count_milestone(&owner_db, f.cabinet_id, f.quote_id, "j3").await, 1);

    dispatch_quote_relances(&app_db).await.unwrap();

    let count: i64 = {
        let mut tx = owner_db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let c = sqlx::query_scalar("SELECT count(*) FROM quote_relance WHERE quote_id = $1")
            .bind(f.quote_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
        c
    };
    assert_eq!(count, 1);

    cleanup_fixtures(&owner_db, &f).await;
}
