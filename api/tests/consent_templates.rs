//! Tests d'intégration : `consent_template` (#7199, DP-F6.b)
//! - `GET`/`POST /v1/cabinet/consent-templates`
//! - `PATCH /v1/cabinet/consent-templates/:id`
//! - `POST /v1/consent-templates/:id/render`

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

const JWT_SECRET: &str = "test-jwt-secret-consent-templates";

/// Modèle global seedé par la migration 0279 (chirurgie orale).
const SEED_GLOBAL_TEMPLATE_ID: &str = "02790000-0000-0000-0000-000000000001";

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
    patient_id: Uuid,
    quote_id: Uuid,
}

/// Seed : cabinet + praticien + patient + devis avec 2 lignes (dents 11/21,
/// actes distincts) — aucun modèle de consentement (créés par les tests).
async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("consent-tmpl+{user_id}@nubia.test"))
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
        .bind(format!("Cabinet ConsentTmpl {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, 'Léa', 'Dupont (test)', '1990-05-17')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'draft', 200.00, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, tooth, unit_amount) \
         VALUES ($1, $2, 'Avulsion', '11', 100.00), ($1, $2, 'Avulsion', '21', 100.00)",
    )
    .bind(cabinet_id)
    .bind(quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        patient_id,
        quote_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM object_storage_blob WHERE key LIKE $1")
        .bind(format!("consentements/{}/%", f.cabinet_id))
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
    sqlx::query("DELETE FROM quote_item WHERE quote_id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consent_template WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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

// ── Test 1 : liste = catalogue global + création cabinet ────────────────────

#[tokio::test]
async fn list_includes_global_catalogue_and_cabinet_template() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/consent-templates",
        &token,
        Some(json!({
            "act_category": "endodontie",
            "title": "Modèle cabinet",
            "body_markdown": "Corps du modèle."
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert!(resp["id"].is_string());
    assert_eq!(resp["version"], 1);

    let (status, resp) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/consent-templates",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let templates = resp.as_array().unwrap();
    assert!(templates.len() >= 11, "catalogue (10) + 1 modèle cabinet");
    assert!(templates
        .iter()
        .any(|t| t["id"] == SEED_GLOBAL_TEMPLATE_ID && t["is_global"] == true));
    assert!(templates
        .iter()
        .any(|t| t["title"] == "Modèle cabinet" && t["is_global"] == false));

    cleanup(&db, &f).await;
}

// ── Test 2 : act_category hors catalogue → 422 ───────────────────────────────

#[tokio::test]
async fn create_with_unknown_act_category_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/consent-templates",
        &token,
        Some(json!({
            "act_category": "blanchiment",
            "title": "Invalide",
            "body_markdown": "x"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 3 : PATCH crée une nouvelle version, désactive l'ancienne ──────────

#[tokio::test]
async fn patch_creates_new_version_and_deactivates_old() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/consent-templates",
        &token,
        Some(json!({
            "act_category": "orthodontie",
            "title": "Brouillon",
            "body_markdown": "corps initial"
        })),
    )
    .await;
    let old_id = created["id"].as_str().unwrap().to_string();

    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/consent-templates/{old_id}"),
        &token,
        Some(json!({"title": "Titre final"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let new_id = patched["id"].as_str().unwrap().to_string();
    assert_ne!(
        new_id, old_id,
        "PATCH crée une nouvelle ligne, pas d'édition en place"
    );
    assert_eq!(patched["version"], 2);

    let (_, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/consent-templates",
        &token,
        None,
    )
    .await;
    let templates = list.as_array().unwrap();
    // L'ancienne version est désactivée : plus dans la liste (is_active = true only).
    assert!(!templates.iter().any(|t| t["id"] == old_id));
    let new_tmpl = templates.iter().find(|t| t["id"] == new_id).unwrap();
    assert_eq!(new_tmpl["title"], "Titre final");
    assert_eq!(new_tmpl["body_markdown"], "corps initial");
    assert_eq!(new_tmpl["version"], 2);

    cleanup(&db, &f).await;
}

// ── Test 3b : PATCH sans changement réel → no-op (#7390) ────────────────────

#[tokio::test]
async fn patch_without_real_change_is_a_noop() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/consent-templates",
        &token,
        Some(json!({
            "act_category": "parodontologie",
            "title": "R84 identique",
            "body_markdown": "Texte inchange R84"
        })),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();
    assert_eq!(created["version"], 1);

    // PATCH à valeurs strictement identiques : ne doit rien créer.
    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/consent-templates/{id}"),
        &token,
        Some(json!({
            "act_category": "parodontologie",
            "title": "R84 identique",
            "body_markdown": "Texte inchange R84"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(patched["id"], id, "id stable : aucun changement réel");
    assert_eq!(patched["version"], 1, "pas de nouvelle version");

    // PATCH avec corps vide : chaque champ retombe sur la valeur courante, donc no-op aussi.
    let (status, patched_empty) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/consent-templates/{id}"),
        &token,
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(patched_empty["id"], id);
    assert_eq!(patched_empty["version"], 1);

    // La version courante est toujours active et le modèle apparaît une seule fois.
    let (_, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/consent-templates",
        &token,
        None,
    )
    .await;
    let templates = list.as_array().unwrap();
    assert_eq!(templates.iter().filter(|t| t["id"] == id).count(), 1);

    cleanup(&db, &f).await;
}

// ── Test 3c : PATCH d'une version désactivée → 404, pas de fork (#7388) ─────

#[tokio::test]
async fn patch_on_deactivated_version_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/consent-templates",
        &token,
        Some(json!({
            "act_category": "implantologie",
            "title": "R84 modele test",
            "body_markdown": "corps initial"
        })),
    )
    .await;
    let v1_id = created["id"].as_str().unwrap().to_string();

    // Premier PATCH : v1 -> v2, v1_id désormais désactivé.
    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/consent-templates/{v1_id}"),
        &token,
        Some(json!({"title": "R84 modele test v2"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(patched["version"], 2);

    // Rejouer un PATCH sur v1_id (désactivé) ne doit plus forker la chaîne.
    let (status, retry) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/consent-templates/{v1_id}"),
        &token,
        Some(json!({"title": "R84 zombie"})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(retry["code"], "not_found");

    // Le catalogue actif ne contient toujours qu'une seule lignée « version 2 ».
    let (_, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/consent-templates",
        &token,
        None,
    )
    .await;
    let templates = list.as_array().unwrap();
    assert_eq!(
        templates
            .iter()
            .filter(|t| t["title"].as_str().unwrap_or("").starts_with("R84"))
            .count(),
        1,
        "une seule version active pour cette lignée"
    );

    cleanup(&db, &f).await;
}

// ── Test 4 : RLS — PATCH le modèle d'un autre cabinet → 404 ─────────────────

#[tokio::test]
async fn patch_template_of_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/consent-templates",
        &token,
        Some(json!({
            "act_category": "pedodontie",
            "title": "Cabinet A",
            "body_markdown": "x"
        })),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let other = seed(&db).await;
    let other_token = make_pro_jwt(other.user_id, other.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/consent-templates/{id}"),
        &other_token,
        Some(json!({"title": "Hijack"})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &other).await;
    cleanup(&db, &f).await;
}

// ── Test 5 : PATCH d'un modèle global → 404 (RLS ne couvre pas cabinet_id NULL) ─

#[tokio::test]
async fn patch_global_template_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/consent-templates/{SEED_GLOBAL_TEMPLATE_ID}"),
        &token,
        Some(json!({"title": "Piraté"})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}

// ── Test 6 : rendu — substitution nom/dents/actes, document joignable ───────

#[tokio::test]
async fn render_substitutes_patient_teeth_and_acts_into_document() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/consent-templates/{SEED_GLOBAL_TEMPLATE_ID}/render"),
        &token,
        Some(json!({"quote_id": f.quote_id})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let document_id = resp["document_id"].as_str().unwrap();
    assert!(Uuid::parse_str(document_id).is_ok());
    assert!(resp["size_bytes"].as_i64().unwrap() > 0);
    let body = resp["body"].as_str().unwrap();
    assert!(body.contains("Léa"));
    assert!(body.contains("Dupont"));
    assert!(body.contains("11"));
    assert!(body.contains("21"));
    assert!(body.contains("Avulsion"));

    // Le document est bien un `document` cabinet, catégorie `consentement`,
    // rattaché au bon patient — joignable au devis via DP-F5.b
    // (`POST /v1/cabinet/quotes/:id/attachments`, `kind: "consent"`).
    let row = sqlx::query_as::<_, (String, Uuid)>(
        "SELECT category, patient_id FROM document WHERE id = $1",
    )
    .bind(Uuid::parse_str(document_id).unwrap())
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(row.0, "consentement");
    assert_eq!(row.1, f.patient_id);

    let (status, attach_resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/quotes/{}/attachments", f.quote_id),
        &token,
        Some(json!({"kind": "consent", "document_id": document_id})),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::CREATED,
        "document rendu doit être attachable via DP-F5.b : {attach_resp:?}"
    );

    cleanup(&db, &f).await;
}

// ── Test 7 : rendu — devis d'un autre cabinet → 404 ──────────────────────────

#[tokio::test]
async fn render_with_quote_of_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let other = seed(&db).await;
    let other_token = make_pro_jwt(other.user_id, other.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/consent-templates/{SEED_GLOBAL_TEMPLATE_ID}/render"),
        &other_token,
        Some(json!({"quote_id": f.quote_id})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &other).await;
    cleanup(&db, &f).await;
}
