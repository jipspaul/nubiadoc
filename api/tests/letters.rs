//! Tests d'intégration : moteur de courriers types (#7197)
//! - `GET`/`POST /v1/letter-templates`
//! - `POST /v1/patients/:id/letters`

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

const JWT_SECRET: &str = "test-jwt-secret-letters";

/// Courrier type global seedé par la migration 0267 (convocation).
const SEED_CONVOCATION_ID: &str = "02670000-0000-0000-0000-000000000001";
/// Courrier type global seedé (courrier confrère : `{{correspondant.nom}}`).
const SEED_CONFRERE_ID: &str = "02670000-0000-0000-0000-000000000003";

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
    provider_id: Uuid,
    patient_id: Uuid,
    private_template_id: Uuid,
}

/// Seed : cabinet (adresse + téléphone) + praticien (RPPS, provider listé)
/// + patient (date de naissance) + RDV futur + un modèle privé au cabinet.
async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let private_template_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("letters+{user_id}@nubia.test"))
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
        "INSERT INTO cabinet (id, raison_sociale, specialite, settings) \
         VALUES ($1, $2, 'dentaire', \
                 '{\"address\": \"12 rue des Lilas, 69001 Lyon\", \
                   \"contact\": {\"phone\": \"04 72 00 00 00\"}}'::jsonb)",
    )
    .bind(cabinet_id)
    .bind(format!("Cabinet Letters {cabinet_id}"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id, rpps) VALUES ($1, $2, $3, '10001234567')")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, practitioner_id, cabinet_id, display_name, user_id, is_listed) \
         VALUES ($1, $2, $3, 'Martin Durand', $4, false)",
    )
    .bind(provider_id)
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
        "INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, now() + interval '7 days', now() + interval '7 days 30 minutes', 'confirmed')",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO letter_template (id, cabinet_id, name, kind, body_template) \
         VALUES ($1, $2, 'Modèle privé test', 'autre', \
                 'Bonjour {{patient.prenom}} {{patient.nom}}, RDV le {{rdv.date}} à {{rdv.heure}} au {{cabinet.nom}}.')",
    )
    .bind(private_template_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        prac_id,
        provider_id,
        patient_id,
        private_template_id,
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
        .bind(format!("courriers/{}/%", f.cabinet_id))
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_correspondent WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM audit_log WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM letter_template WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(f.provider_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.prac_id)
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

// ── Test 1 : happy path — rendu PDF avec en-tête cabinet, stocké en document ──

#[tokio::test]
async fn generate_letter_renders_pdf_and_stores_patient_document() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", f.patient_id),
        &token,
        Some(json!({ "template_id": f.private_template_id, "overrides": {} })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");

    let body = resp["body"].as_str().unwrap();
    assert!(
        body.starts_with("Bonjour Léa Dupont (test), RDV le "),
        "{body}"
    );
    assert!(body.contains(&format!("au Cabinet Letters {}.", f.cabinet_id)));
    assert!(!body.contains("{{"));
    assert!(resp["filename"].as_str().unwrap().ends_with(".pdf"));
    assert!(resp["size_bytes"].as_i64().unwrap() > 0);

    let document_id: Uuid = serde_json::from_value(resp["document_id"].clone()).unwrap();
    let doc = sqlx::query(
        "SELECT category, mime_type, storage_key, size_bytes, uploaded_by, patient_id \
         FROM document WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(document_id)
    .bind(f.cabinet_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(doc.try_get::<String, _>("category").unwrap(), "courrier");
    assert_eq!(
        doc.try_get::<String, _>("mime_type").unwrap(),
        "application/pdf"
    );
    assert_eq!(doc.try_get::<Uuid, _>("uploaded_by").unwrap(), f.user_id);
    assert_eq!(doc.try_get::<Uuid, _>("patient_id").unwrap(), f.patient_id);
    let storage_key: String = doc.try_get("storage_key").unwrap();
    let size_bytes: i64 = doc.try_get("size_bytes").unwrap();

    // L'objet est réellement écrit (PostgresObjectStorage) et c'est un PDF
    // qui porte l'en-tête cabinet (raison sociale, adresse, RPPS) et le corps.
    let blob = sqlx::query("SELECT bytes FROM object_storage_blob WHERE key = $1")
        .bind(&storage_key)
        .fetch_one(&db)
        .await
        .unwrap();
    let bytes: Vec<u8> = blob.try_get("bytes").unwrap();
    assert_eq!(bytes.len() as i64, size_bytes);
    assert!(bytes.starts_with(b"%PDF-1.4"));
    let text = String::from_utf8_lossy(&bytes);
    assert!(text.contains(&format!("(Cabinet Letters {}) Tj", f.cabinet_id)));
    assert!(text.contains("(12 rue des Lilas, 69001 Lyon) Tj"));
    assert!(text.contains("RPPS 10001234567"));
    assert!(text.contains("(Page 1/1) Tj"));
    // Les parenthèses du nom patient sont échappées dans le flux PDF.
    assert!(text.contains("Dupont \\(test\\)"));

    let audit = sqlx::query(
        "SELECT 1 FROM audit_log WHERE cabinet_id = $1 AND action = 'generate_letter' \
         AND entity_id = $2",
    )
    .bind(f.cabinet_id)
    .bind(document_id)
    .fetch_optional(&db)
    .await
    .unwrap();
    assert!(audit.is_some());

    cleanup(&db, &f).await;
}

// ── Test 2 : liste = modèles globaux seedés + modèle privé ; isolation tenant ──

#[tokio::test]
async fn list_templates_shows_seed_and_private_but_not_other_cabinet() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let other = seed(&db).await;

    let (status, resp) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/letter-templates",
        &make_pro_jwt(f.user_id, f.cabinet_id, "secretary"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{resp}");
    let items = resp.as_array().unwrap();
    let ids: Vec<String> = items
        .iter()
        .map(|t| t["id"].as_str().unwrap().to_string())
        .collect();
    assert!(ids.contains(&SEED_CONVOCATION_ID.to_string()));
    assert!(ids.contains(&f.private_template_id.to_string()));
    assert!(!ids.contains(&other.private_template_id.to_string()));
    let seed_item = items
        .iter()
        .find(|t| t["id"] == SEED_CONVOCATION_ID)
        .unwrap();
    assert_eq!(seed_item["is_global"], true);
    assert_eq!(seed_item["kind"], "convocation");
    assert!(seed_item["placeholders"]
        .as_array()
        .unwrap()
        .contains(&json!("rdv.date")));

    // Rendu d'un modèle privé d'un AUTRE cabinet → 404 (RLS).
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", f.patient_id),
        &make_pro_jwt(f.user_id, f.cabinet_id, "practitioner"),
        Some(json!({ "template_id": other.private_template_id })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Patient d'un autre cabinet → 404.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", other.patient_id),
        &make_pro_jwt(f.user_id, f.cabinet_id, "practitioner"),
        Some(json!({ "template_id": SEED_CONVOCATION_ID })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &other).await;
    cleanup(&db, &f).await;
}

// ── Test 3 : erreurs — placeholder inconnu (422 + liste), valeur manquante, 501 ──

#[tokio::test]
async fn create_and_generate_report_placeholder_errors() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "admin");

    // POST /v1/letter-templates avec placeholders inconnus → 422 + liste.
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/letter-templates",
        &token,
        Some(json!({
            "name": "Relance devis",
            "kind": "relance",
            "body_template": "{{patient.prenom}}, devis du {{devis.date}} ({{devis.montant}})"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{resp}");
    assert_eq!(resp["code"], "unknown_placeholders");
    assert_eq!(resp["placeholders"], json!(["devis.date", "devis.montant"]));

    // Création valide → 201 + placeholders utilisés.
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/letter-templates",
        &token,
        Some(json!({
            "name": "Attestation cabinet",
            "kind": "attestation",
            "body_template": "Je soussigné {{praticien.nom}} atteste la présence de {{patient.nom}} le {{rdv.date}}."
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");
    assert_eq!(
        resp["placeholders"],
        json!(["praticien.nom", "patient.nom", "rdv.date"])
    );
    let created_id = resp["template_id"].as_str().unwrap().to_string();

    // Admin (pas praticien, mais le RDV a un praticien) → rendu OK.
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", f.patient_id),
        &token,
        Some(json!({ "template_id": created_id })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");
    assert!(resp["body"]
        .as_str()
        .unwrap()
        .starts_with("Je soussigné Martin Durand atteste"));

    // Courrier confrère seedé sans override → correspondant.nom manquant.
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", f.patient_id),
        &token,
        Some(json!({ "template_id": SEED_CONFRERE_ID })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{resp}");
    assert_eq!(resp["code"], "missing_placeholder_values");
    assert_eq!(resp["placeholders"], json!(["correspondant.nom"]));

    // … avec override → 201, et la valeur n'est pas ré-interprétée.
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", f.patient_id),
        &token,
        Some(json!({
            "template_id": SEED_CONFRERE_ID,
            "overrides": { "correspondant.nom": "Dr {{patient.nom}} Petit" }
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");
    assert!(resp["body"]
        .as_str()
        .unwrap()
        .contains("Dr {{patient.nom}} Petit"));

    // Clé d'override inconnue → 422 + liste.
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", f.patient_id),
        &token,
        Some(json!({
            "template_id": SEED_CONVOCATION_ID,
            "overrides": { "patient.email": "x" }
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{resp}");
    assert_eq!(resp["code"], "unknown_placeholders");
    assert_eq!(resp["placeholders"], json!(["patient.email"]));

    // correspondent_id inexistant (ou d'un autre cabinet) → 404 (#7194).
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", f.patient_id),
        &token,
        Some(json!({
            "template_id": SEED_CONFRERE_ID,
            "correspondent_id": Uuid::new_v4()
        })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{resp}");

    // correspondent_id valide → 201, {{correspondant.nom}} résolu automatiquement
    // (sans override) et le document créé référence ce correspondant.
    let correspondent_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO cabinet_correspondent (id, cabinet_id, display_name) \
         VALUES ($1, $2, 'Dr Confrère Test')",
    )
    .bind(correspondent_id)
    .bind(f.cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", f.patient_id),
        &token,
        Some(json!({
            "template_id": SEED_CONFRERE_ID,
            "correspondent_id": correspondent_id
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");
    assert!(
        resp["body"]
            .as_str()
            .unwrap()
            .contains("Cher confrère, chère consœur Dr Confrère Test,"),
        "{resp}"
    );
    let document_id: Uuid = serde_json::from_value(resp["document_id"].clone()).unwrap();
    let doc_correspondent: Uuid =
        sqlx::query("SELECT correspondent_id FROM document WHERE id = $1")
            .bind(document_id)
            .fetch_one(&db)
            .await
            .unwrap()
            .try_get("correspondent_id")
            .unwrap();
    assert_eq!(doc_correspondent, correspondent_id);

    cleanup(&db, &f).await;
}

// ── Test 4 (#7253) : plafond de longueur sur `name` et les valeurs d'`overrides` ──

#[tokio::test]
async fn oversized_name_and_override_value_are_rejected() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "admin");

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/letter-templates",
        &token,
        Some(json!({
            "name": "Z".repeat(20_000),
            "kind": "autre",
            "body_template": "x"
        })),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "un nom de modèle de 20000 caractères doit être refusé : {resp}"
    );

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{}/letters", f.patient_id),
        &token,
        Some(json!({
            "template_id": SEED_CONVOCATION_ID,
            "overrides": { "praticien.nom": "Z".repeat(20_000) }
        })),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "une valeur d'override de 20000 caractères doit être refusée : {resp}"
    );

    cleanup(&db, &f).await;
}

// ── Test 5 : `{{cabinet.adresse}}` retombe sur l'annuaire (#7242) ────────────
//
// Reproduit le cas QA-20260918-R78-2 : un cabinet dont `settings` ne porte pas
// d'adresse, mais dont le praticien a un profil `provider` lié à un
// `establishment` (annuaire) — même mécanisme de repli que
// `appointments_response::fetch_cabinet_for_response` (#3557).
#[tokio::test]
async fn cabinet_adresse_falls_back_to_establishment_directory() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let establishment_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let template_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("letters-annuaire+{user_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();

    // `establishment` est une table plateforme (pas de RLS cabinet) : insérable
    // sans GUC tenant posé.
    sqlx::query(
        "INSERT INTO establishment (id, name, address) \
         VALUES ($1, 'Cabinet annuaire', \
                 '{\"rue\": \"5 avenue Foch\", \"cp\": \"75116\", \"ville\": \"Paris\"}'::jsonb)",
    )
    .bind(establishment_id)
    .execute(&db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    // Cabinet SANS adresse dans `settings`, comme le cabinet Lyon de la QA.
    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite, settings) \
         VALUES ($1, $2, 'dentaire', '{}'::jsonb)",
    )
    .bind(cabinet_id)
    .bind(format!("Cabinet Annuaire {cabinet_id}"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id, rpps) VALUES ($1, $2, $3, '10009999999')")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO provider \
         (id, practitioner_id, cabinet_id, establishment_id, display_name, user_id, is_listed) \
         VALUES ($1, $2, $3, $4, 'Dr Annuaire', $5, false)",
    )
    .bind(provider_id)
    .bind(prac_id)
    .bind(cabinet_id)
    .bind(establishment_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Léa', 'Dupont (test)')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO letter_template (id, cabinet_id, name, kind, body_template) \
         VALUES ($1, $2, 'Modèle annuaire test', 'autre', \
                 'Cabinet {{cabinet.nom}}, adresse : {{cabinet.adresse}}.')",
    )
    .bind(template_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    let token = make_pro_jwt(user_id, cabinet_id, "practitioner");
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/patients/{patient_id}/letters"),
        &token,
        Some(json!({ "template_id": template_id })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");
    assert!(
        resp["body"]
            .as_str()
            .unwrap()
            .contains("5 avenue Foch, 75116 Paris"),
        "{resp}"
    );

    // Nettoyage.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM audit_log WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM letter_template WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM establishment WHERE id = $1")
        .bind(establishment_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
