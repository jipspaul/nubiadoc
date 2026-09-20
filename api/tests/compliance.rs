//! Tests d'intégration : conformité ARS/DMSM (#7170)
//! - `GET`/`POST /v1/cabinet/compliance-items`
//! - `PATCH`/`DELETE /v1/cabinet/compliance-items/:id`
//! - `POST /v1/cabinet/compliance-items/:id/complete`
//! - `POST /v1/patients/:id/custom-device-declarations`

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

const JWT_SECRET: &str = "test-jwt-secret-compliance";

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
    prac_id: Uuid,
    patient_id: Uuid,
    consultation_act_id: Uuid,
}

/// Seed : cabinet + praticien (membre du cabinet) + patient + RDV honoré +
/// acte facturé (utilisable comme `consultation_act_id` de la déclaration
/// DMSM).
async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();
    let consultation_act_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("compliance+{user_id}@nubia.test"))
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
        .bind(format!("Cabinet Compliance {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, 'practitioner')",
    )
    .bind(cabinet_id)
    .bind(user_id)
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
         VALUES ($1, $2, 'Léa', 'Dupont', '1990-05-17')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, now() - interval '2 days', now() - interval '2 days' + interval '30 minutes', 'done')",
    )
    .bind(appointment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO consultation_act \
         (id, cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents) \
         VALUES ($1, $2, $3, $4, $5, 'HBJD001', 'Pose prothèse amovible', 45000)",
    )
    .bind(consultation_act_id)
    .bind(cabinet_id)
    .bind(appointment_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        prac_id,
        patient_id,
        consultation_act_id,
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
        .bind(format!("dmsm/{}/%", f.cabinet_id))
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM custom_device_declaration WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM compliance_item WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
    sqlx::query("DELETE FROM consultation_act WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
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
    let request = match body {
        Some(json) => builder
            .header("Content-Type", "application/json")
            .body(Body::from(json.to_string()))
            .unwrap(),
        None => {
            builder = builder.header("Content-Type", "application/json");
            builder.body(Body::empty()).unwrap()
        }
    };
    let response = app(state).oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

// ── Test 1 : échéancier — alertes J-30/J-7/échu calculées à la lecture ───────

/// #7170 : due_date passées/proches/lointaines produisent les alertes
/// attendues (`overdue`/`due_j7`/`due_j30`), une date lointaine n'en produit
/// aucune.
#[tokio::test]
async fn compliance_items_alert_levels_match_due_date_windows() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let today = chrono::Utc::now().date_naive();
    let due_dates = [
        (today - chrono::Duration::days(3), "overdue"),
        (today + chrono::Duration::days(3), "due_j7"),
        (today + chrono::Duration::days(20), "due_j30"),
        (today + chrono::Duration::days(90), "__none__"),
    ];

    for (due_date, _) in &due_dates {
        let (status, resp) = call(
            state_with(app_pool().await),
            "POST",
            "/v1/cabinet/compliance-items",
            &token,
            Some(json!({
                "kind": "equipment_check",
                "label": format!("Contrôle {due_date}"),
                "equipment_label": "Autoclave-1",
                "due_date": due_date.to_string(),
            })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{resp}");
    }

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/compliance-items",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = list.as_array().unwrap();
    assert_eq!(items.len(), 4);

    for (due_date, expected_alert) in &due_dates {
        let item = items
            .iter()
            .find(|it| it["due_date"] == due_date.to_string())
            .unwrap_or_else(|| panic!("item {due_date} absent de la liste : {items:?}"));
        if *expected_alert == "__none__" {
            assert!(
                item.get("alert_level").is_none(),
                "aucune alerte attendue à 90 jours : {item}"
            );
        } else {
            assert_eq!(item["alert_level"], *expected_alert, "{item}");
        }
    }

    cleanup(&db, &f).await;
}

// ── Test 2 : clôture + récurrence automatique ────────────────────────────────

#[tokio::test]
async fn completing_item_with_recurrence_creates_next_item() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let due_date = chrono::Utc::now().date_naive() - chrono::Duration::days(1);
    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/compliance-items",
        &token,
        Some(json!({
            "kind": "equipment_check",
            "label": "Contrôle annuel autoclave",
            "equipment_label": "Autoclave-1",
            "due_date": due_date.to_string(),
            "recurrence_months": 12
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{created}");
    let item_id = created["item_id"].as_str().unwrap().to_string();

    let (status, completed) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/compliance-items/{item_id}/complete"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{completed}");
    assert_eq!(completed["status"], "done");
    let next_item_id = completed["next_item_id"]
        .as_str()
        .expect("un item récurrent clôturé doit recréer le suivant")
        .to_string();
    assert_ne!(next_item_id, item_id);

    // Clôturer une 2e fois est refusé (pas idempotent).
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/compliance-items/{item_id}/complete"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{resp}");

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/compliance-items",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = list.as_array().unwrap();
    assert_eq!(items.len(), 2, "l'item clôturé + le suivant recréé");

    let next_item = items
        .iter()
        .find(|it| it["id"] == next_item_id)
        .expect("le nouvel item doit être listé");
    assert_eq!(next_item["status"], "pending");
    assert_eq!(
        next_item["due_date"],
        (due_date + chrono::Months::new(12)).to_string(),
        "la nouvelle échéance doit être l'ancienne + recurrence_months, pas depuis la date de clôture"
    );

    let done_item = items.iter().find(|it| it["id"] == item_id).unwrap();
    assert_eq!(done_item["status"], "done");
    assert!(
        done_item.get("alert_level").is_none(),
        "un item done ne doit plus jamais alerter : {done_item}"
    );

    // Un item done n'est plus éditable ni supprimable.
    let (status, resp) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/compliance-items/{item_id}"),
        &token,
        Some(json!({"label": "Nouveau libellé"})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{resp}");

    let (status, resp) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/compliance-items/{item_id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{resp}");

    cleanup(&db, &f).await;
}

// ── Test 3 : item ponctuel (sans récurrence) ne recrée rien ──────────────────

#[tokio::test]
async fn completing_item_without_recurrence_creates_nothing() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/compliance-items",
        &token,
        Some(json!({
            "kind": "training",
            "label": "Formation gestes d'urgence",
            "due_date": (chrono::Utc::now().date_naive() + chrono::Duration::days(10)).to_string(),
        })),
    )
    .await;
    let item_id = created["item_id"].as_str().unwrap().to_string();

    let (status, completed) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/compliance-items/{item_id}/complete"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{completed}");
    assert!(completed.get("next_item_id").is_none());

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/compliance-items",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 1);

    cleanup(&db, &f).await;
}

// ── Test 4 : PATCH édite un item non clôturé ─────────────────────────────────

#[tokio::test]
async fn patch_compliance_item_updates_due_date() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/compliance-items",
        &token,
        Some(json!({
            "kind": "register",
            "label": "Registre DASRI",
            "due_date": (chrono::Utc::now().date_naive() + chrono::Duration::days(40)).to_string(),
        })),
    )
    .await;
    let item_id = created["item_id"].as_str().unwrap().to_string();

    let new_due_date = chrono::Utc::now().date_naive() + chrono::Duration::days(2);
    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/compliance-items/{item_id}"),
        &token,
        Some(json!({ "due_date": new_due_date.to_string() })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{patched}");
    assert_eq!(patched["due_date"], new_due_date.to_string());
    assert_eq!(patched["alert_level"], "due_j7");
    assert_eq!(patched["label"], "Registre DASRI", "champ non fourni conservé");

    cleanup(&db, &f).await;
}

// ── Test 5 : DMSM — happy path, PDF stocké en document patient ──────────────

#[tokio::test]
async fn generate_custom_device_declaration_stores_pdf_document() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/custom-device-declarations", f.patient_id),
        &token,
        Some(json!({
            "lab_name": "Laboratoire Dentaire Occitan",
            "device_description": "Prothèse amovible partielle",
            "consultation_act_id": f.consultation_act_id
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");
    assert!(resp["filename"].as_str().unwrap().ends_with(".pdf"));
    assert!(resp["size_bytes"].as_i64().unwrap() > 0);

    let document_id: Uuid = serde_json::from_value(resp["document_id"].clone()).unwrap();
    let declaration_id: Uuid = serde_json::from_value(resp["declaration_id"].clone()).unwrap();

    let doc = sqlx::query(
        "SELECT category, mime_type, patient_id FROM document WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(document_id)
    .bind(f.cabinet_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(doc.try_get::<String, _>("category").unwrap(), "dmsm");
    assert_eq!(
        doc.try_get::<String, _>("mime_type").unwrap(),
        "application/pdf"
    );
    assert_eq!(doc.try_get::<Uuid, _>("patient_id").unwrap(), f.patient_id);

    let declaration = sqlx::query(
        "SELECT lab_name, device_description, consultation_act_id, document_id \
         FROM custom_device_declaration WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(declaration_id)
    .bind(f.cabinet_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(
        declaration.try_get::<String, _>("lab_name").unwrap(),
        "Laboratoire Dentaire Occitan"
    );
    assert_eq!(
        declaration.try_get::<Uuid, _>("consultation_act_id").unwrap(),
        f.consultation_act_id
    );
    assert_eq!(
        declaration.try_get::<Uuid, _>("document_id").unwrap(),
        document_id
    );

    let storage_key: String = sqlx::query("SELECT storage_key FROM document WHERE id = $1")
        .bind(document_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("storage_key")
        .unwrap();
    let blob = sqlx::query("SELECT bytes FROM object_storage_blob WHERE key = $1")
        .bind(&storage_key)
        .fetch_one(&db)
        .await
        .unwrap();
    let bytes: Vec<u8> = blob.try_get("bytes").unwrap();
    assert!(bytes.starts_with(b"%PDF-1.4"));
    let text = String::from_utf8_lossy(&bytes);
    assert!(text.contains("DMSM"));
    assert!(text.contains("Laboratoire Dentaire Occitan"));

    let audit = sqlx::query(
        "SELECT 1 FROM audit_log WHERE cabinet_id = $1 \
         AND action = 'create_custom_device_declaration' AND entity_id = $2",
    )
    .bind(f.cabinet_id)
    .bind(declaration_id)
    .fetch_optional(&db)
    .await
    .unwrap();
    assert!(audit.is_some());

    cleanup(&db, &f).await;
}

/// `consultation_act_id` d'un autre patient/cabinet → 404 (pré-vérifié).
#[tokio::test]
async fn custom_device_declaration_rejects_unknown_consultation_act() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/custom-device-declarations", f.patient_id),
        &token,
        Some(json!({
            "lab_name": "Labo X",
            "device_description": "Gouttière occlusale",
            "consultation_act_id": Uuid::new_v4()
        })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{resp}");

    cleanup(&db, &f).await;
}

/// `lab_name`/`device_description` blancs → 422.
#[tokio::test]
async fn custom_device_declaration_rejects_blank_fields() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/custom-device-declarations", f.patient_id),
        &token,
        Some(json!({ "lab_name": "   ", "device_description": "Gouttière" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{resp}");

    cleanup(&db, &f).await;
}
