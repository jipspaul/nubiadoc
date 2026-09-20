//! Tests d'intégration : reprise de données (DP-F14.a #7179) —
//! `POST /v1/cabinet/imports`, `POST …/:id/dry-run`, `POST …/:id/run`,
//! `GET …/:id`. Fixtures CSV : `tests/fixtures/import/*.csv` (données
//! fictives). Nécessite `KMS_MASTER_KEY` (posée par le test) et la base
//! (`DATABASE_URL` + `APP_DATABASE_URL`).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::engine::{general_purpose::STANDARD, Engine};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::{json, Value};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{Instant, SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-data-import-7179";
const RPPS: &str = "10001234567";

const PATIENTS_CSV: &str = include_str!("fixtures/import/patients.csv");
const APPOINTMENTS_CSV: &str = include_str!("fixtures/import/appointments.csv");

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

fn ensure_kms() {
    if std::env::var("KMS_MASTER_KEY").is_err() {
        std::env::set_var("KMS_MASTER_KEY", STANDARD.encode([7u8; 32]));
    }
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

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
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

/// Comme `make_pro_jwt`, mais pose `secretariat_id` (R10 : scope la vision
/// patients du secrétariat) — requis pour reproduire #7480.
fn make_secretary_jwt(user_id: Uuid, cabinet_id: Uuid, secretariat_id: Uuid) -> String {
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
            "role": "secretary",
            "secretariat_id": secretariat_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
            "kind": "patient",
            "account_id": Uuid::new_v4(),
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    admin_id: Uuid,
    prac_user_id: Uuid,
    secretariat_id: Uuid,
}

/// Cabinet + admin + 1 praticien (RPPS `10001234567`, cible des RDV) + 1
/// secrétariat (scope R10 des tokens `secretary`).
async fn insert_fixture(db: &PgPool, tag: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let admin_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();

    for (id, label) in [(admin_id, "admin"), (prac_user_id, "prac")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(id)
        .bind(format!("import7179-{tag}-{label}+{id}@nubia.test"))
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
        .bind(format!("Cabinet Import7179 {tag} {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO practitioner (id, cabinet_id, user_id, rpps, specialite) \
         VALUES ($1, $2, $3, $4, 'dentaire')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(prac_user_id)
    .bind(RPPS)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query("INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec Import7179')")
        .bind(secretariat_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        admin_id,
        prac_user_id,
        secretariat_id,
    }
}

/// Best-effort, une transaction par table : `audit_log` est append-only
/// (trigger), son DELETE échoue sans bloquer le reste.
async fn cleanup(db: &PgPool, f: &Fixture) {
    for sql in [
        "DELETE FROM audit_log WHERE cabinet_id = $1",
        "DELETE FROM data_import_job WHERE cabinet_id = $1",
        "DELETE FROM patient_merge_candidate WHERE cabinet_id = $1",
        "DELETE FROM appointment WHERE cabinet_id = $1",
        "DELETE FROM patient WHERE cabinet_id = $1",
        "DELETE FROM practitioner WHERE cabinet_id = $1",
        "DELETE FROM secretariat WHERE cabinet_id = $1",
        "DELETE FROM cabinet WHERE id = $1",
    ] {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        let ok = sqlx::query(sql)
            .bind(f.cabinet_id)
            .execute(&mut *tx)
            .await
            .is_ok();
        if ok {
            tx.commit().await.ok();
        } else {
            tx.rollback().await.ok();
        }
    }
    for id in [f.admin_id, f.prac_user_id] {
        sqlx::query("DELETE FROM app_user WHERE id = $1")
            .bind(id)
            .execute(db)
            .await
            .ok();
    }
}

fn multipart(kind: &str, csv: &str) -> (String, Vec<u8>) {
    let boundary = "----TestBoundary7179";
    let body = format!(
        "--{boundary}\r\n\
         Content-Disposition: form-data; name=\"kind\"\r\n\r\n\
         {kind}\r\n\
         --{boundary}\r\n\
         Content-Disposition: form-data; name=\"source_system\"\r\n\r\n\
         Doctolib\r\n\
         --{boundary}\r\n\
         Content-Disposition: form-data; name=\"file\"; filename=\"export.csv\"\r\n\
         Content-Type: text/csv\r\n\r\n\
         {csv}\r\n\
         --{boundary}--\r\n"
    );
    (
        format!("multipart/form-data; boundary={boundary}"),
        body.into_bytes(),
    )
}

async fn upload(db: PgPool, token: &str, kind: &str, csv: &str) -> (StatusCode, Value) {
    let (content_type, body) = multipart(kind, csv);
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/imports")
                .header("content-type", content_type)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let json = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, json)
}

async fn call(db: PgPool, token: &str, method: &str, uri: &str) -> (StatusCode, Value) {
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method(method)
                .uri(uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let json = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, json)
}

async fn count(db: &PgPool, cabinet_id: Uuid, table: &str) -> i64 {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let n: i64 = sqlx::query_scalar(&format!(
        "SELECT count(*) FROM {table} WHERE cabinet_id = $1 AND deleted_at IS NULL"
    ))
    .bind(cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    n
}

fn actions(report: &Value, action: &str) -> usize {
    report["lines"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|l| l["action"] == action)
        .count()
}

/// Happy path complet : upload → dry-run (rien d'écrit) → run → re-run
/// sans doublon (patients puis RDV), rapport ligne à ligne + GET.
#[tokio::test]
async fn csv_pipeline_upload_dry_run_run_is_idempotent() {
    if !db_available() {
        return;
    }
    ensure_kms();
    let db = owner_pool().await;
    let f = insert_fixture(&db, "happy").await;
    let token = make_pro_jwt(f.admin_id, f.cabinet_id, "admin");

    // ── Upload patients ──
    let (status, job) = upload(app_pool().await, &token, "csv_patients", PATIENTS_CSV).await;
    assert_eq!(status, StatusCode::CREATED, "{job}");
    assert_eq!(job["status"], "pending");
    assert_eq!(job["kind"], "csv_patients");
    assert_eq!(job["source_system"], "Doctolib");
    assert_eq!(job["total_count"], 20);
    assert_eq!(job["report"]["mode"], "upload");
    assert_eq!(job["report"]["errors"], 2, "{}", job["report"]);
    let job_id = job["id"].as_str().unwrap().to_string();

    // ── Dry-run : rapport complet, aucune écriture ──
    let (status, job) = call(
        app_pool().await,
        &token,
        "POST",
        &format!("/v1/cabinet/imports/{job_id}/dry-run"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["status"], "pending");
    assert!(job["dry_run_at"].is_string());
    assert_eq!(job["report"]["mode"], "dry_run");
    assert_eq!(job["report"]["created"], 18, "{}", job["report"]);
    assert_eq!(job["report"]["errors"], 2);
    assert_eq!(count(&db, f.cabinet_id, "patient").await, 0);
    // Erreurs de lignes : nom vide (ligne 20) et date invalide (ligne 21).
    let errors: Vec<u64> = job["report"]["lines"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|l| l["action"] == "error")
        .map(|l| l["line"].as_u64().unwrap())
        .collect();
    assert_eq!(errors, vec![20, 21]);

    // ── Run ──
    let (status, job) = call(
        app_pool().await,
        &token,
        "POST",
        &format!("/v1/cabinet/imports/{job_id}/run"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["status"], "completed");
    assert_eq!(job["imported_count"], 18);
    assert_eq!(job["skipped_count"], 0);
    assert_eq!(job["error_count"], 2);
    assert_eq!(job["report"]["mode"], "run");
    assert_eq!(actions(&job["report"], "created"), 18);
    assert_eq!(count(&db, f.cabinet_id, "patient").await, 18);

    // INS (ligne P017) chiffré + haché, jamais en clair.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let (ct, hash, contact): (Option<Vec<u8>>, Option<String>, Value) = sqlx::query_as(
        "SELECT ins_ciphertext, ins_hash, contact FROM patient \
         WHERE cabinet_id = $1 AND external_ref = 'P017'",
    )
    .bind(f.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    let (first, last, birth): (String, String, Option<chrono::NaiveDate>) = sqlx::query_as(
        "SELECT first_name, last_name, birth_date FROM patient \
         WHERE cabinet_id = $1 AND external_ref = 'P001'",
    )
    .bind(f.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    let ct = ct.expect("INS chiffré");
    assert!(!ct.windows(15).any(|w| w == b"185129912345678"));
    assert!(hash.is_some());
    assert_eq!(contact["tel"], "0699001122");
    assert_eq!((first.as_str(), last.as_str()), ("Alice", "Durand"));
    assert_eq!(birth, chrono::NaiveDate::from_ymd_opt(1985, 4, 3));

    // ── Re-run du même fichier : aucun doublon, tout `unchanged` ──
    let (status, job) = call(
        app_pool().await,
        &token,
        "POST",
        &format!("/v1/cabinet/imports/{job_id}/run"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["imported_count"], 0);
    assert_eq!(job["skipped_count"], 18);
    assert_eq!(job["error_count"], 2);
    assert_eq!(count(&db, f.cabinet_id, "patient").await, 18);

    // Même fichier re-uploadé sans clés externes → rattachement par
    // nom + prénom + naissance, toujours 18 patients.
    let no_refs: String = PATIENTS_CSV
        .lines()
        .enumerate()
        .map(|(i, l)| {
            if i == 0 {
                l.to_string()
            } else {
                let mut cols: Vec<&str> = l.split(';').collect();
                cols[0] = "";
                cols.join(";")
            }
        })
        .collect::<Vec<_>>()
        .join("\n");
    let (_, job2) = upload(app_pool().await, &token, "csv_patients", &no_refs).await;
    let job2_id = job2["id"].as_str().unwrap();
    let (status, job2) = call(
        app_pool().await,
        &token,
        "POST",
        &format!("/v1/cabinet/imports/{job2_id}/run"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job2}");
    assert_eq!(job2["imported_count"], 0, "{}", job2["report"]);
    assert_eq!(job2["skipped_count"], 18);
    assert_eq!(count(&db, f.cabinet_id, "patient").await, 18);

    // ── RDV : 6 créés, 4 erreurs (chevauchement, patient/praticien inconnus,
    //    fin avant début), puis re-run sans doublon ──
    let (status, job) = upload(
        app_pool().await,
        &token,
        "csv_appointments",
        APPOINTMENTS_CSV,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{job}");
    let rdv_job_id = job["id"].as_str().unwrap().to_string();
    let (status, job) = call(
        app_pool().await,
        &token,
        "POST",
        &format!("/v1/cabinet/imports/{rdv_job_id}/run"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["status"], "completed");
    assert_eq!(job["imported_count"], 6, "{}", job["report"]);
    assert_eq!(job["error_count"], 4);
    let by_ref = |r: &str| -> Value {
        job["report"]["lines"]
            .as_array()
            .unwrap()
            .iter()
            .find(|l| l["external_ref"] == r)
            .cloned()
            .unwrap()
    };
    assert_eq!(by_ref("R004")["action"], "created"); // via nom + prénom + naissance
    assert!(by_ref("R006")["message"]
        .as_str()
        .unwrap()
        .contains("chevauchement"));
    assert!(by_ref("R007")["message"]
        .as_str()
        .unwrap()
        .contains("patient introuvable"));
    assert!(by_ref("R008")["message"]
        .as_str()
        .unwrap()
        .contains("praticien introuvable"));
    assert_eq!(by_ref("R010")["action"], "error");
    assert_eq!(count(&db, f.cabinet_id, "appointment").await, 6);

    let (status, job) = call(
        app_pool().await,
        &token,
        "POST",
        &format!("/v1/cabinet/imports/{rdv_job_id}/run"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["imported_count"], 0);
    assert_eq!(job["skipped_count"], 6);
    assert_eq!(count(&db, f.cabinet_id, "appointment").await, 6);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let (status_r003, starts_r001): (String, chrono::DateTime<chrono::Utc>) = sqlx::query_as(
        "SELECT a.status, b.starts_at FROM appointment a, appointment b \
         WHERE a.cabinet_id = $1 AND a.external_ref = 'R003' \
           AND b.cabinet_id = $1 AND b.external_ref = 'R001'",
    )
    .bind(f.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    let audits: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit_log WHERE cabinet_id = $1 AND action = 'data_import_run'",
    )
    .bind(f.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(status_r003, "cancelled");
    // 15/01/2024 09:00 Europe/Paris (CET) = 08:00 UTC.
    assert_eq!(starts_r001.to_rfc3339(), "2024-01-15T08:00:00+00:00");
    assert_eq!(audits, 5);

    // ── GET ──
    let (status, got) = call(
        app_pool().await,
        &token,
        "GET",
        &format!("/v1/cabinet/imports/{rdv_job_id}"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(got["id"], rdv_job_id);
    assert_eq!(got["status"], "completed");
    assert_eq!(got["report"]["mode"], "run");

    cleanup(&db, &f).await;
}

/// Isolation tenant : le job du cabinet A est invisible (404) et
/// inexécutable depuis le cabinet B.
#[tokio::test]
async fn import_job_is_isolated_per_cabinet() {
    if !db_available() {
        return;
    }
    ensure_kms();
    let db = owner_pool().await;
    let a = insert_fixture(&db, "iso-a").await;
    let b = insert_fixture(&db, "iso-b").await;
    let token_a = make_pro_jwt(a.admin_id, a.cabinet_id, "admin");
    let token_b = make_pro_jwt(b.admin_id, b.cabinet_id, "admin");

    let (status, job) = upload(app_pool().await, &token_a, "csv_patients", PATIENTS_CSV).await;
    assert_eq!(status, StatusCode::CREATED);
    let job_id = job["id"].as_str().unwrap().to_string();

    for (method, suffix) in [("GET", ""), ("POST", "/dry-run"), ("POST", "/run")] {
        let (status, _) = call(
            app_pool().await,
            &token_b,
            method,
            &format!("/v1/cabinet/imports/{job_id}{suffix}"),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{method} {suffix}");
    }
    assert_eq!(count(&db, a.cabinet_id, "patient").await, 0);
    assert_eq!(count(&db, b.cabinet_id, "patient").await, 0);

    cleanup(&db, &a).await;
    cleanup(&db, &b).await;
}

/// Rôle secrétariat+ : `secretary` (#7465, feature livrée dans
/// app_secretariat) et `practitioner` peuvent importer au même titre que
/// `admin` ; un token non-pro (patient) reste rejeté. `kind` inconnu → 422 ;
/// fichier sans colonne obligatoire → job `failed` (201) dont le run est
/// refusé (409).
#[tokio::test]
async fn import_allows_secretary_plus_rejects_non_pro_and_unparsable_file() {
    if !db_available() {
        return;
    }
    ensure_kms();
    let db = owner_pool().await;
    let f = insert_fixture(&db, "errors").await;
    let admin = make_pro_jwt(f.admin_id, f.cabinet_id, "admin");
    let secretary = make_pro_jwt(f.admin_id, f.cabinet_id, "secretary");
    let practitioner = make_pro_jwt(f.prac_user_id, f.cabinet_id, "practitioner");
    let patient = make_patient_jwt(Uuid::new_v4());

    let (status, _) = upload(app_pool().await, &patient, "csv_patients", PATIENTS_CSV).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, job) = upload(app_pool().await, &secretary, "csv_patients", PATIENTS_CSV).await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(job["status"], "pending");

    let (status, job) = upload(
        app_pool().await,
        &practitioner,
        "csv_patients",
        PATIENTS_CSV,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(job["status"], "pending");

    let (status, body) = upload(app_pool().await, &admin, "dsio", PATIENTS_CSV).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["code"], "validation_error");

    let (status, job) = upload(
        app_pool().await,
        &admin,
        "csv_patients",
        "ref_externe;prenom\nP1;Alice\n",
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(job["status"], "failed");
    assert!(job["report"]["lines"][0]["message"]
        .as_str()
        .unwrap()
        .contains("nom"));
    let job_id = job["id"].as_str().unwrap();
    let (status, body) = call(
        app_pool().await,
        &admin,
        "POST",
        &format!("/v1/cabinet/imports/{job_id}/run"),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "invalid_status");

    let (status, _) = call(
        app_pool().await,
        &admin,
        "GET",
        &format!("/v1/cabinet/imports/{}", Uuid::new_v4()),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}

/// #7480 : un secrétariat qui importe des patients doit ensuite les
/// retrouver dans SA liste/fiche (garde R10, cf. #5428 pour la création
/// walk-in) — la reprise de données posait `created_by_secretariat_id`
/// à `NULL`, ce qui les rendait invisibles au secrétariat qui vient de les
/// créer (visibles seulement du praticien).
#[tokio::test]
async fn imported_patients_are_visible_to_the_importing_secretariat() {
    if !db_available() {
        return;
    }
    ensure_kms();
    let db = owner_pool().await;
    let f = insert_fixture(&db, "r10").await;
    let secretary = make_secretary_jwt(f.admin_id, f.cabinet_id, f.secretariat_id);

    let csv =
        "ref_externe;nom;prenom;date_naissance;telephone;email;adresse;code_postal;ville;ins\n\
               QA1;DupontQA89;Jean;1980-05-04;;jean.dupont.qa89@example.test;;;;\n";

    let (status, job) = upload(app_pool().await, &secretary, "csv_patients", csv).await;
    assert_eq!(status, StatusCode::CREATED, "{job}");
    let job_id = job["id"].as_str().unwrap().to_string();

    let (status, job) = call(
        app_pool().await,
        &secretary,
        "POST",
        &format!("/v1/cabinet/imports/{job_id}/run"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["imported_count"], 1, "{}", job["report"]);
    let patient_id = job["report"]["lines"][0]["entity_id"]
        .as_str()
        .unwrap()
        .to_string();

    let (status, list) = call(
        app_pool().await,
        &secretary,
        "GET",
        "/v1/cabinet/patients?q=DupontQA89",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{list}");
    assert_eq!(
        list["data"].as_array().unwrap().len(),
        1,
        "patient importé absent de la liste du secrétariat importateur : {list}"
    );

    let (status, detail) = call(
        app_pool().await,
        &secretary,
        "GET",
        &format!("/v1/cabinet/patients/{patient_id}"),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::OK,
        "fiche patient importé inaccessible au secrétariat importateur : {detail}"
    );

    cleanup(&db, &f).await;
}

/// Done-when de l'issue : 1 000 patients fictifs importés (upload + dry-run
/// + run) en < 30 s, avec rapport, puis re-run sans doublon.
#[tokio::test]
async fn imports_1000_generated_patients_under_30_seconds() {
    if !db_available() {
        return;
    }
    ensure_kms();
    let db = owner_pool().await;
    let f = insert_fixture(&db, "perf").await;
    let token = make_pro_jwt(f.admin_id, f.cabinet_id, "admin");

    let mut csv = String::from(
        "ref_externe;nom;prenom;date_naissance;telephone;email;adresse;code_postal;ville\n",
    );
    for i in 0..1000 {
        csv.push_str(&format!(
            "G{i:04};Nom{i};Prenom{};{:02}/{:02}/{};06{i:08};g{i}@example.test;{i} rue Test;69{:03};Lyon\n",
            i % 7,
            1 + i % 28,
            1 + i % 12,
            1950 + i % 60,
            i % 1000
        ));
    }

    let started = Instant::now();
    let (status, job) = upload(app_pool().await, &token, "csv_patients", &csv).await;
    assert_eq!(status, StatusCode::CREATED, "{job}");
    assert_eq!(job["total_count"], 1000);
    let job_id = job["id"].as_str().unwrap().to_string();
    let (status, job) = call(
        app_pool().await,
        &token,
        "POST",
        &format!("/v1/cabinet/imports/{job_id}/dry-run"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["report"]["created"], 1000);
    let (status, job) = call(
        app_pool().await,
        &token,
        "POST",
        &format!("/v1/cabinet/imports/{job_id}/run"),
    )
    .await;
    let elapsed = started.elapsed();
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["imported_count"], 1000);
    assert_eq!(job["error_count"], 0);
    assert_eq!(job["report"]["lines"].as_array().unwrap().len(), 1000);
    assert!(
        elapsed.as_secs() < 30,
        "upload + dry-run + run de 1 000 patients en {elapsed:?} (> 30 s)"
    );
    assert_eq!(count(&db, f.cabinet_id, "patient").await, 1000);

    let (status, job) = call(
        app_pool().await,
        &token,
        "POST",
        &format!("/v1/cabinet/imports/{job_id}/run"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["imported_count"], 0);
    assert_eq!(job["skipped_count"], 1000);
    assert_eq!(count(&db, f.cabinet_id, "patient").await, 1000);

    cleanup(&db, &f).await;
}
