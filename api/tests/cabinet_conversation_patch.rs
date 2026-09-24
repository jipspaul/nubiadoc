//! Tests d'intégration : `PATCH /v1/cabinet/conversations/:id` — qualification
//! (#7151, doc12 §18 : inbox secrétariat).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-cabinet-conversation-patch";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn owner_pool() -> PgPool {
    let url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_owner@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

fn state() -> AppState {
    AppState {
        db: PgPool::connect_lazy(
            &std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
        )
        .unwrap(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

fn make_pro_jwt(
    user_id: Uuid,
    cabinet_id: Uuid,
    role: &str,
    secretariat_id: Option<Uuid>,
) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "secretariat_id": secretariat_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    secretary_user_id: Uuid,
    prac_id: Uuid,
    conversation_id: Uuid,
    secretariat_id: Uuid,
}

async fn setup(db: &PgPool, prefix: &str) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let secretary_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();

    for (user_id, tag) in [(secretary_user_id, "sec"), (prac_user_id, "prac")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(user_id)
        .bind(format!("cc-patch-{prefix}-{tag}+{user_id}@nubia.test"))
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
        .bind(format!("Cabinet CC Patch {prefix} {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, 'secretary')",
    )
    .bind(cabinet_id)
    .bind(secretary_user_id)
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
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
         VALUES ($1, $2, $3, $4, 'Dr. Test', true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Secrétariat CC Patch')",
    )
    .bind(secretariat_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO provider_secretariat (provider_id, secretariat_id, active) VALUES ($1, $2, true)",
    )
    .bind(provider_id)
    .bind(secretariat_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Claire', 'Patch')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // RDV déjà existant : requis par le filtre R10 (#5715) qui scope l'accès
    // secrétaire au(x) patient(s) suivi(s) par son secrétariat.
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, now() - interval '1 day', \
                 now() - interval '1 day' + interval '30 min', 'confirmed')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO conversation (id, cabinet_id, patient_id, scope, status) \
         VALUES ($1, $2, $3, 'patient_cabinet', 'open')",
    )
    .bind(conversation_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        secretary_user_id,
        prac_id,
        conversation_id,
        secretariat_id,
    }
}

async fn teardown(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM audit_log WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM conversation WHERE id = $1")
        .bind(f.conversation_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider_secretariat WHERE secretariat_id = $1")
        .bind(f.secretariat_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM secretariat WHERE id = $1")
        .bind(f.secretariat_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_membership WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.secretary_user_id)
        .execute(db)
        .await
        .ok();
}

async fn patch(
    token: &str,
    uri: String,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app(state())
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(uri)
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, json)
}

// ── Qualification complète → 200, colonnes posées en base ───────────────────

#[tokio::test]
async fn secretary_patches_qualification_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "ok").await;

    let assignee_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(assignee_id)
    .bind(format!("cc-patch-ok-assignee+{assignee_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, 'practitioner')")
        .bind(f.cabinet_id)
        .bind(assignee_id)
        .execute(&db)
        .await
        .unwrap();

    let token = make_pro_jwt(
        f.secretary_user_id,
        f.cabinet_id,
        "secretary",
        Some(f.secretariat_id),
    );

    let (status, json) = patch(
        &token,
        format!("/v1/cabinet/conversations/{}", f.conversation_id),
        json!({
            "origin": "phone",
            "motif": "Douleur dentaire",
            "priority": "urgent",
            "assignee_user_id": assignee_id,
            "status": "in_progress",
            "summary": "Rappel patient prévu demain matin."
        }),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "body: {json}");
    assert_eq!(json["origin"], "phone");
    assert_eq!(json["motif"], "Douleur dentaire");
    assert_eq!(json["priority"], "urgent");
    assert_eq!(json["assignee_user_id"], assignee_id.to_string());
    assert_eq!(json["status"], "in_progress");
    assert_eq!(json["summary"], "Rappel patient prévu demain matin.");

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query(
        "SELECT origin, motif, priority, assignee_user_id, status, summary \
         FROM conversation WHERE id = $1",
    )
    .bind(f.conversation_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let db_status: String = row.try_get("status").unwrap();
    let db_priority: Option<String> = row.try_get("priority").unwrap();
    let db_assignee: Option<Uuid> = row.try_get("assignee_user_id").unwrap();
    assert_eq!(db_status, "in_progress");
    assert_eq!(db_priority.as_deref(), Some("urgent"));
    assert_eq!(db_assignee, Some(assignee_id));

    // Partiel : un second PATCH sans `priority` la laisse inchangée.
    let (status, json) = patch(
        &token,
        format!("/v1/cabinet/conversations/{}", f.conversation_id),
        json!({ "status": "done" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {json}");
    assert_eq!(json["status"], "done");
    assert_eq!(
        json["priority"], "urgent",
        "un champ absent du PATCH doit rester inchangé"
    );

    // audit_log — au moins une entrée de qualification liée à la conversation.
    let audit_row = sqlx::query(
        "SELECT entity FROM audit_log \
         WHERE cabinet_id = $1 AND entity_id = $2 AND action = 'update_conversation_qualification'",
    )
    .bind(f.cabinet_id)
    .bind(f.conversation_id)
    .fetch_optional(&db)
    .await
    .unwrap();
    assert!(
        audit_row.is_some(),
        "audit_log attendu pour la qualification"
    );

    teardown(&db, &f).await;
}

// ── `status` hors énum → 422 ─────────────────────────────────────────────────

#[tokio::test]
async fn invalid_status_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "invstatus").await;

    let token = make_pro_jwt(
        f.secretary_user_id,
        f.cabinet_id,
        "secretary",
        Some(f.secretariat_id),
    );
    let (status, _) = patch(
        &token,
        format!("/v1/cabinet/conversations/{}", f.conversation_id),
        json!({ "status": "bogus" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    teardown(&db, &f).await;
}

// ── `assignee_user_id` hors cabinet → 404 ────────────────────────────────────

#[tokio::test]
async fn assignee_outside_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "badassignee").await;

    let token = make_pro_jwt(
        f.secretary_user_id,
        f.cabinet_id,
        "secretary",
        Some(f.secretariat_id),
    );
    let (status, _) = patch(
        &token,
        format!("/v1/cabinet/conversations/{}", f.conversation_id),
        json!({ "assignee_user_id": Uuid::new_v4() }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    teardown(&db, &f).await;
}

// ── Conversation hors tenant → 404 ───────────────────────────────────────────

#[tokio::test]
async fn cross_tenant_patch_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "crosstenant").await;

    let other_token = make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "practitioner", None);
    let (status, _) = patch(
        &other_token,
        format!("/v1/cabinet/conversations/{}", f.conversation_id),
        json!({ "status": "done" }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    teardown(&db, &f).await;
}

#[tokio::test]
async fn patch_no_jwt_returns_401() {
    let response = app(state())
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/conversations/{}", Uuid::new_v4()))
                .header("content-type", "application/json")
                .body(Body::from(json!({ "status": "done" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
