//! Tests d'intégration : GET /v1/cabinet/patients + POST /v1/cabinet/patients (§14)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

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

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    }
}

/// Enregistre un pro, renvoie `(access_token, user_id, cabinet_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Patients Test", "siret": null, "specialite": "dentaire" },
        "practitioner": { "first_name": "Paul", "last_name": "Durand", "rpps": null, "adeli": null }
    });
    let response = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/pro/register")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let token = v["access_token"].as_str().unwrap().to_string();
    let user_id: Uuid = v["account_id"].as_str().unwrap().parse().unwrap();
    let cabinet_id: Uuid = v["cabinet_id"].as_str().unwrap().parse().unwrap();
    (token, user_id, cabinet_id)
}

/// Crée un `patient_account` en DB (rôle owner, hors RLS cabinet), renvoie son `id`.
async fn create_patient_account(owner: &PgPool, email: &str) -> Uuid {
    let id = Uuid::new_v4();
    // Crée d'abord l'app_user associé.
    let user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'x', 'patient')",
    )
    .bind(user_id)
    .bind(email)
    .execute(owner)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Marie', 'Curie')",
    )
    .bind(id)
    .bind(user_id)
    .execute(owner)
    .await
    .unwrap();
    id
}

/// Crée un JWT signé `kind=patient` (pour tester le 403 patient).
fn make_patient_token(sub: Uuid, account_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        account_id: Uuid,
        exp: u64,
    }
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "patient".into(),
            account_id,
            exp,
        },
        &EncodingKey::from_secret(b"test-secret"),
    )
    .unwrap()
}

// ── Test 1 : GET /v1/cabinet/patients → 200 avec token pro valide ─────────────

#[tokio::test]
async fn list_cabinet_patients_returns_200() {
    if !db_available() {
        return;
    }
    let email = format!("list_patients_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &email).await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["data"].is_array(), "data doit être un tableau");
    assert!(v["page"].is_object(), "page doit être un objet");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 2 : GET /v1/cabinet/patients sans token → 401 ───────────────────────

#[tokio::test]
async fn list_cabinet_patients_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : GET /v1/cabinet/patients avec token patient → 403 ───────────────

#[tokio::test]
async fn list_cabinet_patients_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let account_id = Uuid::new_v4();
    let token = make_patient_token(account_id, account_id);
    let db = app_pool().await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

// ── Test 4 : POST /v1/cabinet/patients → 201 + patient_id retourné ──────────

#[tokio::test]
async fn create_cabinet_patient_returns_201() {
    if !db_available() {
        return;
    }
    let pro_email = format!("create_patient_pro_{}@test.local", Uuid::new_v4());
    let patient_email = format!("create_patient_acct_{}@test.local", Uuid::new_v4());
    let owner = owner_pool().await;
    let db = app_pool().await;

    let (token, _, _) = register_pro(db.clone(), &pro_email).await;
    let patient_account_id = create_patient_account(&owner, &patient_email).await;

    let body = json!({ "patient_account_id": patient_account_id, "note": "Test" });
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(
        v["patient_id"]
            .as_str()
            .and_then(|s| s.parse::<Uuid>().ok())
            .is_some(),
        "patient_id doit être un UUID valide"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1 OR email = $2")
        .bind(&pro_email)
        .bind(&patient_email)
        .execute(&owner)
        .await
        .ok();
}

// ── Test 5 : POST /v1/cabinet/patients sans token → 401 ──────────────────────

#[tokio::test]
async fn create_cabinet_patient_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let body = json!({ "patient_account_id": Uuid::new_v4() });
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 6 : POST /v1/cabinet/patients avec token patient → 403 ──────────────

#[tokio::test]
async fn create_cabinet_patient_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let account_id = Uuid::new_v4();
    let token = make_patient_token(account_id, account_id);
    let db = app_pool().await;
    let body = json!({ "patient_account_id": Uuid::new_v4() });

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

// ── Helper : JWT pro (practitioner/admin/secretary) sans passer par register ──

fn make_pro_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: role.to_string(),
            exp,
        },
        &EncodingKey::from_secret(b"test-secret"),
    )
    .unwrap()
}

// ── Tests GET /v1/cabinet/patients/:id ────────────────────────────────────────

#[tokio::test]
async fn get_cabinet_patient_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn get_cabinet_patient_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let account_id = Uuid::new_v4();
    let token = make_patient_token(account_id, account_id);
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn get_cabinet_patient_unknown_id_returns_404() {
    if !db_available() {
        return;
    }
    let email = format!("get_patient_404_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &email).await;
    let unknown_id = Uuid::new_v4();

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", unknown_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Tests GET /v1/cabinet/patients/:id/notes ──────────────────────────────────

#[tokio::test]
async fn list_patient_notes_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/notes", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn list_patient_notes_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let account_id = Uuid::new_v4();
    let token = make_patient_token(account_id, account_id);
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/notes", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

/// Secretary → 403 sur les notes cliniques (ProPractitionerClaims, §07 R.4127-72).
#[tokio::test]
async fn list_patient_notes_secretary_token_returns_403() {
    if !db_available() {
        return;
    }
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "secretary");
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/notes", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

// ── Tests GET /v1/cabinet/patients/:id/medical-record ─────────────────────────

#[tokio::test]
async fn get_medical_record_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-record",
                    Uuid::new_v4()
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn get_medical_record_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let account_id = Uuid::new_v4();
    let token = make_patient_token(account_id, account_id);
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-record",
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

/// Secretary → 403 sur le dossier médical (ProPractitionerClaims, §07 R.4127-72).
#[tokio::test]
async fn get_medical_record_secretary_token_returns_403() {
    if !db_available() {
        return;
    }
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "secretary");
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-record",
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

// ── Tests GET /v1/cabinet/patients/:id/dental-chart ───────────────────────────

#[tokio::test]
async fn get_dental_chart_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/dental-chart",
                    Uuid::new_v4()
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn get_dental_chart_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let account_id = Uuid::new_v4();
    let token = make_patient_token(account_id, account_id);
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/dental-chart",
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

/// Secretary → 403 sur l'odontogramme (ProPractitionerClaims, §07 R.4127-72).
#[tokio::test]
async fn get_dental_chart_secretary_token_returns_403() {
    if !db_available() {
        return;
    }
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "secretary");
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/dental-chart",
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

// ── Tests GET /v1/cabinet/patients/:id/documents ──────────────────────────────

#[tokio::test]
async fn list_patient_documents_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/documents", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn list_patient_documents_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let account_id = Uuid::new_v4();
    let token = make_patient_token(account_id, account_id);
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/documents", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

// ── Tests supplémentaires T-API-AUDIT-A003 ────────────────────────────────────

/// Secrétaire → 200 sur `GET /v1/cabinet/patients/:id` MAIS sans champs cliniques
/// (`medical_record`, `notes` absents — R.4127-72 §07 §4.1).
#[tokio::test]
async fn get_cabinet_patient_secretary_sees_admin_only_200() {
    if !db_available() {
        return;
    }
    let pro_email = format!("sec_admin_pro_{}@test.local", Uuid::new_v4());
    let patient_email = format!("sec_admin_patient_{}@test.local", Uuid::new_v4());
    let owner = owner_pool().await;
    let db = app_pool().await;

    let (pro_token, _, cabinet_id) = register_pro(db.clone(), &pro_email).await;
    let patient_account_id = create_patient_account(&owner, &patient_email).await;

    // Crée le patient dans ce cabinet via le token pro.
    let body = json!({ "patient_account_id": patient_account_id });
    let resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", pro_token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let patient_id = v["patient_id"].as_str().unwrap().to_string();

    // Token secrétaire pour le même cabinet.
    let sec_token = make_pro_token(Uuid::new_v4(), cabinet_id, "secretary");

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", patient_id))
                .header("Authorization", format!("Bearer {}", sec_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    // R.4127-72 : la secrétaire ne voit PAS les sections cliniques.
    assert!(
        v.get("medical_record").is_none(),
        "secretary should not see medical_record"
    );
    assert!(v.get("notes").is_none(), "secretary should not see notes");
    // Mais les champs admin sont présents.
    assert!(v["first_name"].is_string(), "first_name should be present");

    sqlx::query("DELETE FROM app_user WHERE email = $1 OR email = $2")
        .bind(&pro_email)
        .bind(&patient_email)
        .execute(&owner)
        .await
        .ok();
}

/// `GET /v1/cabinet/patients/:id/notes` — patient inconnu → 404.
#[tokio::test]
async fn list_patient_notes_unknown_patient_returns_404() {
    if !db_available() {
        return;
    }
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "practitioner");
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/notes", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

/// `GET /v1/cabinet/patients/:id/notes` — patient existe mais aucun RDV avec ce praticien
/// → 403 (E.2.16.c, §14 accès journal clinique).
#[tokio::test]
async fn list_patient_notes_no_appointment_returns_403() {
    if !db_available() {
        return;
    }
    let pro_email = format!("notes_no_appt_pro_{}@test.local", Uuid::new_v4());
    let patient_email = format!("notes_no_appt_patient_{}@test.local", Uuid::new_v4());
    let owner = owner_pool().await;
    let db = app_pool().await;

    let (token, _, _) = register_pro(db.clone(), &pro_email).await;
    let patient_account_id = create_patient_account(&owner, &patient_email).await;

    // Crée le patient dans le cabinet (sans créer de RDV).
    let body = json!({ "patient_account_id": patient_account_id });
    let resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let patient_id = v["patient_id"].as_str().unwrap().to_string();

    // Aucun appointment → E.2.16.c : 403.
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/notes", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    sqlx::query("DELETE FROM app_user WHERE email = $1 OR email = $2")
        .bind(&pro_email)
        .bind(&patient_email)
        .execute(&owner)
        .await
        .ok();
}

/// `GET /v1/cabinet/patients/:id/medical-record` — patient inconnu → 404.
#[tokio::test]
async fn get_medical_record_unknown_patient_returns_404() {
    if !db_available() {
        return;
    }
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "practitioner");
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-record",
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

/// `GET /v1/cabinet/patients/:id/dental-chart` — patient inconnu → 404.
#[tokio::test]
async fn get_dental_chart_unknown_patient_returns_404() {
    if !db_available() {
        return;
    }
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "practitioner");
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/dental-chart",
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

/// `GET /v1/cabinet/patients/:id/documents` — patient inconnu → 404.
#[tokio::test]
async fn list_patient_documents_unknown_patient_returns_404() {
    if !db_available() {
        return;
    }
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "practitioner");
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/documents", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);
}

/// `POST /v1/cabinet/patients` idempotent : deux appels successifs retournent le même `patient_id`.
#[tokio::test]
async fn create_cabinet_patient_idempotent_same_id() {
    if !db_available() {
        return;
    }
    let pro_email = format!("idem_pro_{}@test.local", Uuid::new_v4());
    let patient_email = format!("idem_patient_{}@test.local", Uuid::new_v4());
    let owner = owner_pool().await;
    let db = app_pool().await;

    let (token, _, _) = register_pro(db.clone(), &pro_email).await;
    let patient_account_id = create_patient_account(&owner, &patient_email).await;

    let body = json!({ "patient_account_id": patient_account_id });

    // Premier appel.
    let resp1 = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp1.status(), StatusCode::CREATED);
    let bytes1 = axum::body::to_bytes(resp1.into_body(), usize::MAX)
        .await
        .unwrap();
    let v1: serde_json::Value = serde_json::from_slice(&bytes1).unwrap();
    let patient_id_1 = v1["patient_id"].as_str().unwrap().to_string();

    // Deuxième appel identique (idempotence).
    let resp2 = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp2.status(), StatusCode::CREATED);
    let bytes2 = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&bytes2).unwrap();
    let patient_id_2 = v2["patient_id"].as_str().unwrap().to_string();

    assert_eq!(
        patient_id_1, patient_id_2,
        "idempotent POST should return same patient_id"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1 OR email = $2")
        .bind(&pro_email)
        .bind(&patient_email)
        .execute(&owner)
        .await
        .ok();
}

/// `GET /v1/cabinet/patients?limit=0` → clamped à 1, `page.limit == 1` (edge case pagination).
#[tokio::test]
async fn list_cabinet_patients_limit_clamp_returns_200() {
    if !db_available() {
        return;
    }
    let email = format!("limit_clamp_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &email).await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients?limit=0")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    // limit=0 est clampé à 1 par le handler.
    assert_eq!(
        v["page"]["limit"].as_i64().unwrap(),
        1,
        "limit=0 should be clamped to 1"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

/// Pagination offset : seed 60 patients, GET limit=20 → 20, GET limit=20 offset=20 → 20 différents.
#[tokio::test]
async fn list_cabinet_patients_pagination_offset() {
    if !db_available() {
        return;
    }
    let pro_email = format!("pag_pro_{}@test.local", Uuid::new_v4());
    let owner = owner_pool().await;
    let db = app_pool().await;

    let (token, _, cabinet_id) = register_pro(db.clone(), &pro_email).await;

    // Seed 60 patients directly (owner pool bypasses RLS).
    let mut acct_emails: Vec<String> = Vec::new();
    for i in 0..60i32 {
        let user_id = Uuid::new_v4();
        let acct_id = Uuid::new_v4();
        let email = format!("pag_pat_{}_{}@test.local", i, Uuid::new_v4());
        acct_emails.push(email.clone());
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'x', 'patient')",
        )
        .bind(user_id)
        .bind(&email)
        .execute(&owner)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES ($1, $2, 'P', 'Q')",
        )
        .bind(acct_id)
        .bind(user_id)
        .execute(&owner)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO patient (cabinet_id, patient_account_id, first_name, last_name, contact) \
             VALUES ($1, $2, 'P', 'Q', '{}'::jsonb)",
        )
        .bind(cabinet_id)
        .bind(acct_id)
        .execute(&owner)
        .await
        .unwrap();
    }

    // limit=20 → exactement 20 résultats.
    let resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients?limit=20")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let page1_ids: Vec<String> = v["data"]
        .as_array()
        .unwrap()
        .iter()
        .map(|x| x["id"].as_str().unwrap().to_string())
        .collect();
    assert_eq!(page1_ids.len(), 20, "limit=20 doit retourner 20 items");

    // limit=20 offset=20 → 20 patients différents de la page 1.
    let resp2 = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients?limit=20&offset=20")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp2.status(), StatusCode::OK);
    let bytes2 = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&bytes2).unwrap();
    let page2_ids: Vec<String> = v2["data"]
        .as_array()
        .unwrap()
        .iter()
        .map(|x| x["id"].as_str().unwrap().to_string())
        .collect();
    assert_eq!(page2_ids.len(), 20, "offset=20 doit retourner 20 items");
    for id in &page2_ids {
        assert!(
            !page1_ids.contains(id),
            "page 2 ne doit pas chevaucher page 1"
        );
    }

    // Cleanup.
    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&pro_email)
        .execute(&owner)
        .await
        .ok();
    for email in &acct_emails {
        sqlx::query("DELETE FROM app_user WHERE email = $1")
            .bind(email)
            .execute(&owner)
            .await
            .ok();
    }
}

/// Catégorie inconnue → 200 avec `data: []` (early return avant toute requête DB).
#[tokio::test]
async fn list_patient_documents_unknown_category_returns_200_empty() {
    if !db_available() {
        return;
    }
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "practitioner");
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/documents?category=inconnue",
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(
        v["data"].as_array().unwrap().is_empty(),
        "data doit être vide pour une catégorie inconnue"
    );
}
