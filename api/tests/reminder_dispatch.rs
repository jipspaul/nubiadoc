//! Tests d'intégration : worker de dispatch des rappels RDV (#4034).
//!
//! Couvre les deux critères d'acceptation de l'issue :
//! - un reminder `pending` échu passe à `sent` après exécution du job
//!   (patient avec un device actif) ;
//! - un device absent produit `failed` sans panic (patient sans device, ou
//!   patient non lié à un compte).

use nubia_api::{dispatch_pending_reminders, StubJobDispatcher, StubSmsSender};
use sqlx::PgPool;
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

struct Fixture {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    patient_account_user_id: Option<Uuid>,
    patient_account_id: Option<Uuid>,
    patient_id: Uuid,
    appointment_id: Uuid,
    reminder_id: Uuid,
}

/// Insère cabinet + praticien + patient + RDV + reminder `pending` échu.
/// `with_account_and_device` : si `true`, le patient est lié à un
/// `patient_account`/`app_user` avec un `device` actif (chemin `sent`
/// attendu). Si `false`, le patient n'est lié à AUCUN compte (chemin
/// `failed` attendu — cas "patient jamais inscrit côté app").
async fn insert_fixture(db: &PgPool, suffix: &str, with_account_and_device: bool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();
    let reminder_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("reminder-dispatch-prac-{suffix}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    let (patient_account_user_id, patient_account_id) = if with_account_and_device {
        let account_user_id = Uuid::new_v4();
        let account_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
        )
        .bind(account_user_id)
        .bind(format!("reminder-dispatch-pat-{suffix}@nubia.test"))
        .execute(db)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
             VALUES ($1, $2, 'Marc', 'Dubois')",
        )
        .bind(account_id)
        .bind(account_user_id)
        .execute(db)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO device (id, app_user_id, fcm_token, platform, active) \
             VALUES ($1, $2, 'fake-fcm-token', 'android', true)",
        )
        .bind(Uuid::new_v4())
        .bind(account_user_id)
        .execute(db)
        .await
        .unwrap();
        (Some(account_user_id), Some(account_id))
    } else {
        (None, None)
    };

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet ReminderDispatch {suffix}"))
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
    .bind(patient_account_id)
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

    // scheduled_at dans le passé : échu, ramassé par due_reminders_for_dispatch().
    sqlx::query(
        "INSERT INTO reminder \
         (id, cabinet_id, appointment_id, patient_id, scheduled_at, kind, channel, status) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', 'rdv_rappel', 'push', 'pending')",
    )
    .bind(reminder_id)
    .bind(cabinet_id)
    .bind(appointment_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        prac_user_id,
        patient_account_user_id,
        patient_account_id,
        patient_id,
        appointment_id,
        reminder_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
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

    if let Some(account_id) = f.patient_account_id {
        sqlx::query("DELETE FROM patient_account WHERE id = $1")
            .bind(account_id)
            .execute(db)
            .await
            .ok();
    }
    if let Some(account_user_id) = f.patient_account_user_id {
        sqlx::query("DELETE FROM device WHERE app_user_id = $1")
            .bind(account_user_id)
            .execute(db)
            .await
            .ok();
        sqlx::query("DELETE FROM app_user WHERE id = $1")
            .bind(account_user_id)
            .execute(db)
            .await
            .ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : reminder pending échu + device actif → sent ─────────────────────

#[tokio::test]
async fn dispatch_marks_reminder_sent_when_device_active() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixture(&owner, &Uuid::new_v4().to_string(), true).await;

    let summary = dispatch_pending_reminders(&app_db, &StubJobDispatcher, &StubSmsSender)
        .await
        .unwrap();
    assert!(
        summary.sent >= 1,
        "au moins ce reminder doit être compté sent (summary={summary:?})"
    );

    let status: String = sqlx::query_scalar("SELECT status FROM reminder WHERE id = $1")
        .bind(f.reminder_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_eq!(status, "sent");

    let sent_at: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("SELECT sent_at FROM reminder WHERE id = $1")
            .bind(f.reminder_id)
            .fetch_one(&owner)
            .await
            .unwrap();
    assert!(sent_at.is_some(), "sent_at doit être posé");

    // Une notification in-app doit avoir été créée pour ce patient.
    let notif_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM notification WHERE app_user_id = $1 AND kind = 'rdv_rappel'",
    )
    .bind(f.patient_account_user_id.unwrap())
    .fetch_one(&owner)
    .await
    .unwrap();
    assert_eq!(notif_count, 1, "une notification in-app doit être créée");

    sqlx::query("DELETE FROM notification WHERE app_user_id = $1")
        .bind(f.patient_account_user_id.unwrap())
        .execute(&owner)
        .await
        .ok();
    cleanup(&owner, &f).await;
}

// ── Test 2 : patient sans compte/device → failed, pas de panic ───────────────

#[tokio::test]
async fn dispatch_marks_reminder_failed_when_no_device() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixture(&owner, &Uuid::new_v4().to_string(), false).await;

    let summary = dispatch_pending_reminders(&app_db, &StubJobDispatcher, &StubSmsSender)
        .await
        .unwrap();
    assert!(
        summary.failed >= 1,
        "au moins ce reminder doit être compté failed (summary={summary:?})"
    );

    let status: String = sqlx::query_scalar("SELECT status FROM reminder WHERE id = $1")
        .bind(f.reminder_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_eq!(status, "failed");

    let sent_at: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("SELECT sent_at FROM reminder WHERE id = $1")
            .bind(f.reminder_id)
            .fetch_one(&owner)
            .await
            .unwrap();
    assert!(
        sent_at.is_none(),
        "sent_at ne doit pas être posé sur un échec"
    );

    cleanup(&owner, &f).await;
}

// ── Test 3 (#4389) : rappel recall_annual (appointment_id NULL) ne bloque
// pas le balayage — un rappel RDV légitime, dû dans la MÊME passe, doit
// quand même être traité (sent), pas juste "aucune erreur retournée" ──────

#[tokio::test]
async fn dispatch_does_not_abort_on_null_appointment_recall_reminder() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let app_db = app_pool().await;

    // RDV légitime avec device actif : doit rester "sent" même si une ligne
    // recall_annual (appointment_id NULL) est due dans la même passe.
    let f = insert_fixture(&owner, &Uuid::new_v4().to_string(), true).await;

    // Rappel de campagne de relance (recall_campaigns.rs) : appointment_id
    // NULL, dû immédiatement — exactement la ligne qui faisait planter tout
    // le balayage avant #4389.
    let recall_cabinet_id = Uuid::new_v4();
    let recall_patient_id = Uuid::new_v4();
    let recall_reminder_id = Uuid::new_v4();
    let mut tx = owner.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(recall_cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(recall_cabinet_id)
        .bind(format!("Cabinet Recall NullAppt {recall_reminder_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'QA', 'Recall')",
    )
    .bind(recall_patient_id)
    .bind(recall_cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO reminder \
         (id, cabinet_id, appointment_id, patient_id, scheduled_at, kind, status) \
         VALUES ($1, $2, NULL, $3, now() - interval '1 hour', 'recall_annual', 'pending')",
    )
    .bind(recall_reminder_id)
    .bind(recall_cabinet_id)
    .bind(recall_patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let summary = dispatch_pending_reminders(&app_db, &StubJobDispatcher, &StubSmsSender)
        .await
        .expect(
            "le balayage ne doit jamais échouer sur une ligne recall_annual (appointment_id NULL)",
        );
    assert!(
        summary.sent >= 1,
        "le rappel RDV légitime doit rester traité (sent) dans la même passe (summary={summary:?})"
    );

    let rdv_status: String = sqlx::query_scalar("SELECT status FROM reminder WHERE id = $1")
        .bind(f.reminder_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_eq!(
        rdv_status, "sent",
        "le rappel RDV légitime ne doit pas être laissé pending par la ligne recall en erreur"
    );

    let recall_status: String = sqlx::query_scalar("SELECT status FROM reminder WHERE id = $1")
        .bind(recall_reminder_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_ne!(
        recall_status, "pending",
        "la ligne recall_annual doit être sortie de pending (traitée, pas laissée due indéfiniment)"
    );

    sqlx::query("DELETE FROM notification WHERE app_user_id = $1")
        .bind(f.patient_account_user_id.unwrap())
        .execute(&owner)
        .await
        .ok();
    cleanup(&owner, &f).await;

    let mut tx = owner.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(recall_cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM reminder WHERE id = $1")
        .bind(recall_reminder_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(recall_patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(recall_cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}
