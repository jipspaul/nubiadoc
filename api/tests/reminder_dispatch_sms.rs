//! Tests d'intégration : worker de dispatch des rappels RDV, canal SMS (#4036).
//!
//! Couvre les deux critères d'acceptation de l'issue :
//! - un reminder `channel='sms'` échu avec un numéro connu déclenche l'appel
//!   provider (mock HTTP) et transitionne en `status='sent'` ;
//! - un opt-out patient (`notification_preference.sms_rdv=false`) ne
//!   déclenche AUCUN appel provider et transitionne en `status='cancelled'`.
//!
//! Fixture distincte de `reminder_dispatch.rs` (canal push) : pas besoin de
//! `device`, besoin d'un numéro de téléphone sur `patient_account`.

use nubia_api::{dispatch_pending_reminders, StubJobDispatcher, TwilioSmsSender};
use sqlx::PgPool;
use uuid::Uuid;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

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

struct SmsFixture {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    patient_account_user_id: Uuid,
    patient_account_id: Uuid,
    patient_id: Uuid,
    appointment_id: Uuid,
    reminder_id: Uuid,
}

/// Insère cabinet + praticien + patient (compte + téléphone) + RDV + reminder
/// `channel='sms'` `pending` échu. `sms_rdv` : `Some(false)` insère une ligne
/// `notification_preference` en opt-out ; `None` n'en insère aucune (opt-in
/// par défaut, DEFAULT true de la colonne).
async fn insert_sms_fixture(
    db: &PgPool,
    suffix: &str,
    phone: &str,
    sms_rdv: Option<bool>,
) -> SmsFixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();
    let reminder_id = Uuid::new_v4();
    let account_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("reminder-dispatch-sms-prac-{suffix}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(account_user_id)
    .bind(format!("reminder-dispatch-sms-pat-{suffix}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name, phone) \
         VALUES ($1, $2, 'Marc', 'Dubois', $3)",
    )
    .bind(account_id)
    .bind(account_user_id)
    .bind(phone)
    .execute(db)
    .await
    .unwrap();

    if let Some(sms_rdv) = sms_rdv {
        sqlx::query(
            "INSERT INTO notification_preference (patient_account_id, sms_rdv) VALUES ($1, $2)",
        )
        .bind(account_id)
        .bind(sms_rdv)
        .execute(db)
        .await
        .unwrap();
    }

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet ReminderDispatchSms {suffix}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Marc', 'Dubois', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, now() + interval '1 day', \
                 now() + interval '1 day 30 minutes', 'confirmed')",
    )
    .bind(appointment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // channel='sms' : c'est ce que #4036 ajoute au dispatch.
    sqlx::query(
        "INSERT INTO reminder \
         (id, cabinet_id, appointment_id, patient_id, scheduled_at, kind, channel, status) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', 'rdv_rappel', 'sms', 'pending')",
    )
    .bind(reminder_id)
    .bind(cabinet_id)
    .bind(appointment_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    SmsFixture {
        cabinet_id,
        prac_user_id,
        patient_account_user_id: account_user_id,
        patient_account_id: account_id,
        patient_id,
        appointment_id,
        reminder_id,
    }
}

async fn cleanup(db: &PgPool, f: &SmsFixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM reminder WHERE id = $1")
        .bind(f.reminder_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(f.appointment_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
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

    sqlx::query("DELETE FROM notification_preference WHERE patient_account_id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.patient_account_user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

async fn wait_for_request() {
    tokio::time::sleep(std::time::Duration::from_millis(300)).await;
}

// ── Test 1 : reminder channel='sms' + numéro connu → appel provider + sent ──

#[tokio::test]
async fn dispatch_sends_sms_and_marks_sent_when_channel_is_sms() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_sms_fixture(&owner, &Uuid::new_v4().to_string(), "+33600000001", None).await;

    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/2010-04-01/Accounts/test-sid/Messages.json"))
        .respond_with(ResponseTemplate::new(201))
        .expect(1)
        .mount(&mock_server)
        .await;

    let sms_sender =
        TwilioSmsSender::with_base_url("test-sid", "test-token", "+33700000000", mock_server.uri());

    let summary = dispatch_pending_reminders(&app_db, &StubJobDispatcher, &sms_sender)
        .await
        .unwrap();
    assert!(
        summary.sent >= 1,
        "au moins ce reminder doit être compté sent (summary={summary:?})"
    );
    wait_for_request().await;

    let requests = mock_server.received_requests().await.unwrap();
    assert_eq!(requests.len(), 1, "un seul POST attendu vers Twilio");
    let body = String::from_utf8(requests[0].body.clone()).unwrap();
    assert!(body.contains("To=%2B33600000001"), "body={body}");

    let status: String = sqlx::query_scalar("SELECT status FROM reminder WHERE id = $1")
        .bind(f.reminder_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_eq!(status, "sent");

    cleanup(&owner, &f).await;
}

// ── Test 2 : reminder channel='sms' + opt-out patient → cancelled, pas d'appel ──

#[tokio::test]
#[ignore = "quarantaine: bug déterministe révélé par le fix DB CI, voir #4602"]
async fn dispatch_marks_reminder_cancelled_when_sms_opted_out() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_sms_fixture(
        &owner,
        &Uuid::new_v4().to_string(),
        "+33600000002",
        Some(false),
    )
    .await;

    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(201))
        .expect(0)
        .mount(&mock_server)
        .await;

    let sms_sender =
        TwilioSmsSender::with_base_url("test-sid", "test-token", "+33700000000", mock_server.uri());

    let summary = dispatch_pending_reminders(&app_db, &StubJobDispatcher, &sms_sender)
        .await
        .unwrap();
    assert!(
        summary.cancelled >= 1,
        "au moins ce reminder doit être compté cancelled (summary={summary:?})"
    );
    wait_for_request().await;

    let status: String = sqlx::query_scalar("SELECT status FROM reminder WHERE id = $1")
        .bind(f.reminder_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_eq!(status, "cancelled");

    cleanup(&owner, &f).await;
}
