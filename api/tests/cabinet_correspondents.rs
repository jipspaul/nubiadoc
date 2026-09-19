//! Tests d'intégration : annuaire des correspondants du cabinet (#7194, DP-F8.b)
//! - `GET`/`POST /v1/cabinet/correspondents`
//! - `PATCH`/`DELETE /v1/cabinet/correspondents/:id`
//! - `GET /v1/cabinet/correspondents/:id/stats`

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-cabinet-correspondents";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
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
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    user_id: Uuid,
}

/// Seed : cabinet seul — chaque test crée ses propres correspondants/patients.
async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("correspondents+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Correspondants {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
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
    sqlx::query("DELETE FROM document WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_item WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("UPDATE patient SET referred_by_correspondent_id = NULL WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_correspondent WHERE cabinet_id = $1")
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
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn call(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("Authorization", format!("Bearer {token}"));
    let body = match body {
        Some(v) => {
            builder = builder.header("Content-Type", "application/json");
            Body::from(v.to_string())
        }
        None => Body::empty(),
    };
    let response = app(state)
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

// ── Test 1 : POST + GET — création, tri par nom ──────────────────────────────

#[tokio::test]
async fn create_and_list_correspondents_sorted_by_name() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({
            "display_name": "Dr Zoé Martin",
            "specialty": "Chirurgien-dentiste",
            "email": "zoe.martin@confrere.test",
            "phone": "04 72 00 00 00",
            "address": "3 rue de la Paix, 75002 Paris",
            "rpps": "10001234567",
            "notes": "Adresse volontiers les cas d'orthodontie."
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");
    assert!(resp["id"].is_string());
    assert_eq!(resp["display_name"], "Dr Zoé Martin");
    assert_eq!(resp["specialty"], "Chirurgien-dentiste");
    assert_eq!(resp["email"], "zoe.martin@confrere.test");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({"display_name": "Dr Anas Belkacem"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, resp) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/correspondents",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = resp.as_array().unwrap();
    assert_eq!(items.len(), 2);
    // Trié par display_name : "Anas" avant "Zoé".
    assert_eq!(items[0]["display_name"], "Dr Anas Belkacem");
    assert_eq!(items[1]["display_name"], "Dr Zoé Martin");
    assert!(items[1]["specialty"].is_string());

    cleanup(&db, &f).await;
}

// ── Test 2 : validation — nom blanc / email invalide → 422 ───────────────────

#[tokio::test]
async fn create_rejects_blank_name_and_invalid_email() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({"display_name": "   "})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({"display_name": "Dr Test", "email": "pas-un-email"})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 3 : PATCH — met à jour, efface un champ blanc, laisse les absents ──

#[tokio::test]
async fn patch_updates_fields_and_blank_clears_them() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({
            "display_name": "Dr Initial",
            "specialty": "ORL",
            "phone": "0100000000"
        })),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/correspondents/{id}"),
        &token,
        Some(json!({"display_name": "Dr Renommé", "specialty": ""})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{patched}");
    assert_eq!(patched["display_name"], "Dr Renommé");
    assert!(patched["specialty"].is_null(), "champ blanc → effacé");
    assert_eq!(
        patched["phone"], "0100000000",
        "champ absent du PATCH → inchangé"
    );

    cleanup(&db, &f).await;
}

// ── Test 4 : RLS — PATCH/DELETE le correspondant d'un autre cabinet → 404 ───

#[tokio::test]
async fn patch_and_delete_of_other_cabinet_return_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({"display_name": "Cabinet A"})),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let other = seed(&db).await;
    let other_token = make_pro_jwt(other.user_id, other.cabinet_id, "secretary");

    let (status, _) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/correspondents/{id}"),
        &other_token,
        Some(json!({"display_name": "Hijack"})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/correspondents/{id}"),
        &other_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &other).await;
    cleanup(&db, &f).await;
}

// ── Test 5 : DELETE — retire un correspondant non référencé ─────────────────

#[tokio::test]
async fn delete_removes_unreferenced_correspondent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({"display_name": "À supprimer"})),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/correspondents/{id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (_, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/correspondents",
        &token,
        None,
    )
    .await;
    assert!(!list.as_array().unwrap().iter().any(|c| c["id"] == id));

    // Rejouer la suppression → 404 (déjà supprimé).
    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/correspondents/{id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}

// ── Test 6 : DELETE d'un correspondant référencé par un patient → 409 ───────

#[tokio::test]
async fn delete_referenced_correspondent_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({"display_name": "Référencé"})),
    )
    .await;
    let correspondent_id = created["id"].as_str().unwrap().to_string();

    let patient_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, referred_by_correspondent_id) \
         VALUES ($1, $2, 'Léa', 'Dupont', $3)",
    )
    .bind(patient_id)
    .bind(f.cabinet_id)
    .bind(Uuid::parse_str(&correspondent_id).unwrap())
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let (status, resp) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/correspondents/{correspondent_id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{resp}");
    assert_eq!(resp["code"], "correspondent_in_use");

    cleanup(&db, &f).await;
}

// ── Test 7 : stats — adressages, CA facturé (devis signés only), courriers ──

#[tokio::test]
async fn stats_report_referred_patients_billed_revenue_and_letters_sent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({"display_name": "Dr Adresseur"})),
    )
    .await;
    let correspondent_id = Uuid::parse_str(created["id"].as_str().unwrap()).unwrap();

    let referred_signed = Uuid::new_v4();
    let referred_draft = Uuid::new_v4();
    let not_referred = Uuid::new_v4();
    let signed_quote_id = Uuid::new_v4();
    let draft_quote_id = Uuid::new_v4();
    let document_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, referred_by_correspondent_id) \
         VALUES ($1, $2, 'Léa', 'Signée', $3), ($4, $2, 'Nino', 'Brouillon', $3), \
                ($5, $2, 'Sans', 'Adressage', NULL)",
    )
    .bind(referred_signed)
    .bind(f.cabinet_id)
    .bind(correspondent_id)
    .bind(referred_draft)
    .bind(not_referred)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Devis signé sur le patient adressé : compté dans le CA facturé.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'signed', 350.00, 'EUR')",
    )
    .bind(signed_quote_id)
    .bind(f.cabinet_id)
    .bind(referred_signed)
    .execute(&mut *tx)
    .await
    .unwrap();
    // Devis brouillon (non signé) sur l'autre patient adressé : jamais du CA facturé.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'draft', 999.00, 'EUR')",
    )
    .bind(draft_quote_id)
    .bind(f.cabinet_id)
    .bind(referred_draft)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Un courrier adressé à ce correspondant.
    sqlx::query(
        "INSERT INTO document \
         (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256, \
          correspondent_id) \
         VALUES ($1, $2, $3, 'courrier', 'courriers/test/x.pdf', 'x.pdf', 'application/pdf', \
                 $4, $5)",
    )
    .bind(document_id)
    .bind(f.cabinet_id)
    .bind(referred_signed)
    .bind("a".repeat(64))
    .bind(correspondent_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    let (status, resp) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/correspondents/{correspondent_id}/stats"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{resp}");
    assert_eq!(resp["referred_patients_count"], 2);
    assert_eq!(resp["billed_revenue_cents"], 35000);
    assert_eq!(resp["letters_sent_count"], 1);

    cleanup(&db, &f).await;
}

// ── Test 8 : stats d'un correspondant inexistant → 404 ───────────────────────

#[tokio::test]
async fn stats_of_unknown_correspondent_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (status, _) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/correspondents/{}/stats", Uuid::new_v4()),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}
