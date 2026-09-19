//! Tests d'intégration : `GET`/`POST /reservation/confirmer` — écran 3 du
//! tunnel SSR public (#6954, #6826, #6733).
//!
//! Le QA constatait une page statique identique quels que soient les
//! paramètres (même sans aucun), sans formulaire ni lien, et qui affirmait
//! « Votre créneau est retenu » alors qu'aucun hold n'existait. Ces tests
//! verrouillent le contrat rendu côté serveur : récapitulatif réel
//! (praticien, date, heure), formulaire HTML classique (sans JS) avec
//! consentement, 404 sans sélection, 410 sur un créneau perdu, et une
//! soumission qui crée réellement le compte + la réservation.

use axum::{
    body::Body,
    http::{header, Request, StatusCode},
    response::Response,
};
use sqlx::{PgPool, Row};
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{web_tunnel, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-web-tunnel-confirm";

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

async fn tunnel() -> axum::Router {
    web_tunnel::router(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    })
}

async fn body_text(response: Response) -> String {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    String::from_utf8(bytes.to_vec()).unwrap()
}

async fn get(path: &str) -> Response {
    tunnel()
        .await
        .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
        .await
        .unwrap()
}

async fn post_form(form: &str) -> Response {
    tunnel()
        .await
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/reservation/confirmer")
                .header(
                    header::CONTENT_TYPE,
                    "application/x-www-form-urlencoded; charset=utf-8",
                )
                .body(Body::from(form.to_string()))
                .unwrap(),
        )
        .await
        .unwrap()
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

struct Fixture {
    provider_id: Uuid,
    slot_id: Uuid,
    display_name: String,
}

/// Praticien listé (cabinet + practitioner + provider) + créneau
/// `open`/`online_booking` demain — même schéma que `bookings_post.rs`
/// (le booking résout cabinet/practitioner via le créneau). Nom unique pour
/// que le lien retour vers la fiche soit vérifiable sans collision avec les
/// autres agents sur la base partagée.
async fn insert_provider_with_open_slot(db: &PgPool, suffix: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let slot_id = Uuid::new_v4();
    let display_name = format!("Dr Wtc {}", &suffix[..8]);

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("wtc-pro-{suffix}@nubia.test"))
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
        .bind(format!("Cabinet WTC {suffix}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, $5, true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(practitioner_id)
    .bind(user_id)
    .bind(&display_name)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
         VALUES ($1, $2, $3, $4, now() + interval '1 day', now() + interval '1 day 30 minutes', 'open', true)",
    )
    .bind(slot_id)
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(practitioner_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        provider_id,
        slot_id,
        display_name,
    }
}

/// Un autre patient retient le créneau (même fonction SQL que `POST
/// /v1/slots/:id/hold`) — simule le créneau perdu entre le `GET` et le
/// `POST` du visiteur.
async fn hold_by_someone_else(db: &PgPool, slot_id: Uuid, suffix: &str) {
    let user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("wtc-other-{suffix}@nubia.test"))
    .execute(db)
    .await
    .unwrap();
    let row = sqlx::query("SELECT claim_result FROM claim_and_hold_slot($1, $2, $3)")
        .bind(slot_id)
        .bind(user_id)
        .bind(Uuid::new_v4().to_string())
        .fetch_one(db)
        .await
        .unwrap();
    let result: Option<String> = row.try_get("claim_result").unwrap();
    assert_eq!(result.as_deref(), Some("claimed"));
}

async fn count_users_with_email(db: &PgPool, email: &str) -> i64 {
    sqlx::query("SELECT count(*) AS n FROM app_user WHERE email = $1")
        .bind(email)
        .fetch_one(db)
        .await
        .unwrap()
        .try_get::<i64, _>("n")
        .unwrap()
}

fn confirm_url(f: &Fixture) -> String {
    format!(
        "/reservation/confirmer?providerId={}&slotId={}",
        f.provider_id, f.slot_id
    )
}

fn valid_form(f: &Fixture, email: &str, with_consent: bool) -> String {
    let mut form = format!(
        "providerId={}&slotId={}&prenom=Julie&nom=Martin&naissance=1990-01-01\
         &telephone=%2B33612345678&email={}&motif=Contr%C3%B4le",
        f.provider_id,
        f.slot_id,
        email.replace('@', "%40"),
    );
    if with_consent {
        form.push_str("&consentement=on");
    }
    form
}

// ── GET ──────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn get_without_selection_is_404_without_form_and_without_hold_claim() {
    if !db_available() {
        return;
    }
    let response = get("/reservation/confirmer").await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    let html = body_text(response).await;
    assert!(!html.contains("<form"), "aucun formulaire sans créneau");
    assert!(
        !html.to_lowercase().contains("retenu"),
        "ne doit jamais affirmer qu'un créneau est retenu"
    );
    assert!(
        html.contains(r#"href="/""#),
        "un lien de sortie vers la recherche"
    );

    // UUID malformé : même repli propre, pas une erreur brute d'Axum.
    let response = get("/reservation/confirmer?providerId=deadbeef&slotId=NOT-A-UUID").await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    let html = body_text(response).await;
    assert!(html.contains("<h1>"));
    assert!(!html.contains("Failed to deserialize"));
}

#[tokio::test]
async fn get_with_a_real_slot_shows_recap_and_form_without_false_hold_claim() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let f = insert_provider_with_open_slot(&db, &suffix).await;

    let response = get(&confirm_url(&f)).await;
    assert_eq!(response.status(), StatusCode::OK);
    let html = body_text(response).await;

    // Récapitulatif réel : le praticien choisi, et le créneau (demain).
    assert!(html.contains(&f.display_name), "nom du praticien absent");
    let tomorrow = chrono::Utc::now() + chrono::Duration::days(1);
    assert!(
        html.contains(&format!(" {} ", chrono::Datelike::day(&tomorrow))),
        "jour du créneau absent : {html}"
    );

    // Formulaire HTML classique, sans JS (CSP du tunnel).
    assert!(html.contains(r#"<form method="post" action="/reservation/confirmer""#));
    assert!(html.contains(&format!(r#"name="providerId" value="{}""#, f.provider_id)));
    assert!(html.contains(&format!(r#"name="slotId" value="{}""#, f.slot_id)));
    for field in ["prenom", "nom", "telephone", "email"] {
        assert!(
            html.contains(&format!(r#"name="{field}""#)),
            "champ {field}"
        );
    }
    assert!(
        html.contains(r#"type="checkbox" name="consentement""#),
        "case de consentement absente"
    );
    assert!(html.contains(r#"<button type="submit">"#));
    assert!(!html.contains("<script"), "aucun script (CSP du tunnel)");

    // Aucun hold n'est posé par le GET : la page ne doit pas le prétendre.
    assert!(
        !html.to_lowercase().contains("retenu"),
        "affirme un hold inexistant : {html}"
    );
    let status: String = sqlx::query("SELECT status FROM availability_slot WHERE id = $1")
        .bind(f.slot_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("status")
        .unwrap();
    assert_eq!(status, "open");

    // Les paramètres sont bien lus : un autre couple donne une autre page.
    let other = get(&format!(
        "/reservation/confirmer?providerId={}&slotId={}",
        f.provider_id,
        Uuid::new_v4()
    ))
    .await;
    assert_ne!(other.status(), StatusCode::OK);
}

#[tokio::test]
async fn get_with_a_lost_or_foreign_slot_is_410_and_links_back_to_the_provider() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let f = insert_provider_with_open_slot(&db, &suffix).await;
    let other = insert_provider_with_open_slot(&db, &Uuid::new_v4().to_string()).await;

    // Couple incohérent : créneau d'un autre praticien.
    let response = get(&format!(
        "/reservation/confirmer?providerId={}&slotId={}",
        f.provider_id, other.slot_id
    ))
    .await;
    assert_eq!(response.status(), StatusCode::GONE);

    // Créneau retenu entre-temps par un autre visiteur (hold réel).
    hold_by_someone_else(&db, f.slot_id, &suffix).await;
    let response = get(&confirm_url(&f)).await;
    assert_eq!(response.status(), StatusCode::GONE);
    let html = body_text(response).await;
    assert!(html.contains("plus disponible"));
    assert!(!html.contains("<form"));
    assert!(
        html.contains(&format!(
            r#"href="/{}""#,
            f.display_name.to_lowercase().replace(' ', "-")
        )),
        "lien retour vers la fiche du praticien attendu : {html}"
    );

    // Praticien inconnu → 404.
    let response = get(&format!(
        "/reservation/confirmer?providerId={}&slotId={}",
        Uuid::new_v4(),
        f.slot_id
    ))
    .await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

// ── POST ─────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn post_creates_the_account_and_books_the_slot() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let f = insert_provider_with_open_slot(&db, &suffix).await;
    let email = format!("wtc-visitor-{suffix}@nubia.test");

    let response = post_form(&valid_form(&f, &email, true)).await;
    assert_eq!(response.status(), StatusCode::OK);
    let html = body_text(response).await;
    assert!(html.contains("Rendez-vous confirmé"));
    assert!(html.contains(&f.display_name));
    assert!(html.contains(&email));

    // Compte créé, créneau consommé, rendez-vous enregistré.
    assert_eq!(count_users_with_email(&db, &email).await, 1);
    let status: String = sqlx::query("SELECT status FROM availability_slot WHERE id = $1")
        .bind(f.slot_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("status")
        .unwrap();
    assert_eq!(status, "booked");
    let row = sqlx::query("SELECT motif FROM appointment WHERE slot_id = $1")
        .bind(f.slot_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let motif: Option<String> = row.try_get("motif").unwrap();
    assert_eq!(motif.as_deref(), Some("Contrôle"));

    // Le mot de passe sera choisi via le lien envoyé : token posé.
    let has_reset_token: bool =
        sqlx::query("SELECT password_reset_token IS NOT NULL AS t FROM app_user WHERE email = $1")
            .bind(&email)
            .fetch_one(&db)
            .await
            .unwrap()
            .try_get("t")
            .unwrap();
    assert!(has_reset_token);
}

#[tokio::test]
async fn post_without_consent_is_422_and_writes_nothing() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let f = insert_provider_with_open_slot(&db, &suffix).await;
    let email = format!("wtc-noconsent-{suffix}@nubia.test");

    let response = post_form(&valid_form(&f, &email, false)).await;
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
    let html = body_text(response).await;
    assert!(
        html.contains(&format!("slotId={}", f.slot_id)),
        "lien retour au formulaire"
    );

    assert_eq!(count_users_with_email(&db, &email).await, 0);
    let status: String = sqlx::query("SELECT status FROM availability_slot WHERE id = $1")
        .bind(f.slot_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("status")
        .unwrap();
    assert_eq!(status, "open");
}

#[tokio::test]
async fn post_with_oversized_prenom_nom_or_telephone_is_422_and_writes_nothing() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // (valeur par défaut dans `valid_form`, valeur démesurée à substituer)
    let cases = [
        ("prenom=Julie", format!("prenom={}", "P".repeat(20_000))),
        ("nom=Martin", format!("nom={}", "N".repeat(20_000))),
        (
            "telephone=%2B33612345678",
            format!("telephone={}", "0".repeat(20_000)),
        ),
    ];

    for (needle, oversized) in cases {
        let suffix = Uuid::new_v4().to_string();
        let f = insert_provider_with_open_slot(&db, &suffix).await;
        let email = format!("wtc-oversized-{suffix}@nubia.test");
        let form = valid_form(&f, &email, true).replace(needle, &oversized);

        let response = post_form(&form).await;
        assert_eq!(
            response.status(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "champ démesuré ({needle}) doit être refusé"
        );
        assert_eq!(count_users_with_email(&db, &email).await, 0);
    }
}

#[tokio::test]
async fn post_with_a_birth_date_outside_the_120_year_window_is_422_and_writes_nothing() {
    // #7374 : le tunnel SSR public est la seule voie créant un
    // `patient_account` qui ne bornait pas `naissance` — une date dans le
    // futur ou vieille de plus de 120 ans doit être refusée, comme sur les
    // voies authentifiées (#6653, auth/mod.rs).
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let tomorrow = (chrono::Utc::now() + chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    let cases = [
        ("naissance=1990-01-01", "naissance=2099-12-31".to_string()),
        ("naissance=1990-01-01", "naissance=1800-01-01".to_string()),
        ("naissance=1990-01-01", format!("naissance={tomorrow}")),
    ];

    for (needle, out_of_range) in cases {
        let suffix = Uuid::new_v4().to_string();
        let f = insert_provider_with_open_slot(&db, &suffix).await;
        let email = format!("wtc-birthdate-{suffix}@nubia.test");
        let form = valid_form(&f, &email, true).replace(needle, &out_of_range);

        let response = post_form(&form).await;
        assert_eq!(
            response.status(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "naissance hors bornes ({out_of_range}) doit être refusée"
        );
        assert_eq!(count_users_with_email(&db, &email).await, 0);
    }
}

#[tokio::test]
async fn post_on_a_slot_lost_meanwhile_is_410_and_creates_no_account() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let f = insert_provider_with_open_slot(&db, &suffix).await;
    let email = format!("wtc-late-{suffix}@nubia.test");

    // Le visiteur a vu le formulaire…
    assert_eq!(get(&confirm_url(&f)).await.status(), StatusCode::OK);
    // …mais quelqu'un d'autre retient le créneau avant qu'il ne valide.
    hold_by_someone_else(&db, f.slot_id, &suffix).await;

    let response = post_form(&valid_form(&f, &email, true)).await;
    assert_eq!(response.status(), StatusCode::GONE);
    let html = body_text(response).await;
    assert!(html.contains("plus disponible"));
    assert!(!html.contains("confirmé"));
    assert!(
        html.contains(&format!(
            r#"href="/{}""#,
            f.display_name.to_lowercase().replace(' ', "-")
        )),
        "lien retour vers la fiche du praticien attendu : {html}"
    );

    assert_eq!(count_users_with_email(&db, &email).await, 0);
}

#[tokio::test]
async fn post_without_selection_is_404() {
    if !db_available() {
        return;
    }
    let response = post_form("prenom=Julie&nom=Martin").await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}
