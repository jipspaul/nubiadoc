//! Tests d'intégration : GET /v1/notifications

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

const JWT_SECRET: &str = "test-jwt-secret-notifications";

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

fn make_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère une notification avec `data` (JSONB) explicite — pour vérifier la
/// restitution de `data`/`deep_link` (#3863).
async fn insert_notification_with_data(
    app_db: &PgPool,
    user_id: Uuid,
    kind: &str,
    title: &str,
    data: serde_json::Value,
) -> Uuid {
    let id = Uuid::new_v4();
    let mut tx = app_db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO notification \
         (id, app_user_id, kind, title, body_ciphertext, body_key_ref, data) \
         VALUES ($1, $2, $3, $4, '\\x00'::bytea, 'stub', $5)",
    )
    .bind(id)
    .bind(user_id)
    .bind(kind)
    .bind(title)
    .bind(data)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    id
}

/// Insère une notification via nubia_app (RLS : current_user_id = app_user_id).
async fn insert_notification(
    app_db: &PgPool,
    user_id: Uuid,
    kind: &str,
    title: &str,
    is_read: bool,
) -> Uuid {
    let id = Uuid::new_v4();
    let mut tx = app_db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO notification \
         (id, app_user_id, kind, title, body_ciphertext, body_key_ref, is_read) \
         VALUES ($1, $2, $3, $4, '\\x00'::bytea, 'stub', $5)",
    )
    .bind(id)
    .bind(user_id)
    .bind(kind)
    .bind(title)
    .bind(is_read)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    id
}

// ── Test 1 : liste basique → 200 + données ────────────────────────────────────

#[tokio::test]
async fn notifications_list_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-list+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    insert_notification(&app_db, user_id, "rdv", "Votre RDV", false).await;
    insert_notification(&app_db, user_id, "message", "Nouveau message", true).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(v["data"].is_array());
    assert_eq!(v["data"].as_array().unwrap().len(), 2);
    assert!(v["page"]["next_cursor"].is_null());

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : ?unread_only=true → filtre les lues ──────────────────────────────

#[tokio::test]
async fn notifications_unread_only_returns_only_unread() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-unread+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    insert_notification(&app_db, user_id, "rdv", "RDV non lu", false).await;
    insert_notification(&app_db, user_id, "rdv", "RDV lu", true).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications?unread_only=true")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["is_read"], false);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2b : page.unread_count reflète le total, pas la page (#6279) ────────
// Repro exacte de #6279 : badge de la cloche plafonné à `limit` (défaut 20)
// au lieu du total réel de non-lus, un pro avec plus de non-lus que `limit`
// voyait un compteur figé.

#[tokio::test]
async fn notifications_unread_count_reflects_total_not_page_size() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-unread-count+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    // 3 non-lues, 1 lue — mais on ne demande que 2 (`limit=2`), comme le
    // ferait un client qui paginerait au lieu de compter `data.len()`.
    insert_notification(&app_db, user_id, "rdv", "Non lu 1", false).await;
    insert_notification(&app_db, user_id, "rdv", "Non lu 2", false).await;
    insert_notification(&app_db, user_id, "rdv", "Non lu 3", false).await;
    insert_notification(&app_db, user_id, "rdv", "Lu", true).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications?unread_only=true&limit=2")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    // La page ne contient que 2 items (limit)...
    assert_eq!(v["data"].as_array().unwrap().len(), 2);
    assert!(!v["page"]["next_cursor"].is_null());
    // ...mais le total de non-lus reste 3, pas 2 (`data.len()`) ni le
    // total toutes notifications confondues (4).
    assert_eq!(v["page"]["unread_count"], 3);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn notifications_no_jwt_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : pagination cursor → next_cursor puis page 2 ─────────────────────

#[tokio::test]
async fn notifications_pagination_cursor() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-pag+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    // Insert 3 notifications avec des created_at distincts.
    for i in 0u32..3 {
        let id = Uuid::new_v4();
        let mut tx = app_pool().await.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(user_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO notification \
             (id, app_user_id, kind, title, body_ciphertext, body_key_ref, \
              created_at) \
             VALUES ($1, $2, 'rdv', $3, '\\x00'::bytea, 'stub', \
                     now() - ($4 * interval '1 second'))",
        )
        .bind(id)
        .bind(user_id)
        .bind(format!("Notif {i}"))
        .bind(i as i64)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Page 1 : limit=2
    let resp1 = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications?limit=2")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp1.status(), StatusCode::OK);
    let body1 = axum::body::to_bytes(resp1.into_body(), usize::MAX)
        .await
        .unwrap();
    let v1: serde_json::Value = serde_json::from_slice(&body1).unwrap();
    assert_eq!(v1["data"].as_array().unwrap().len(), 2);
    let cursor = v1["page"]["next_cursor"].as_str().unwrap().to_string();

    // Page 2 : use cursor
    let app_db2 = app_pool().await;
    let state2 = AppState {
        db: app_db2,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Le curseur contient uniquement des chiffres, un `|` et un UUID : sûr en query string.
    let resp2 = app(state2)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/notifications?limit=2&cursor={cursor}"))
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp2.status(), StatusCode::OK);
    let body2 = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&body2).unwrap();
    assert_eq!(v2["data"].as_array().unwrap().len(), 1);
    assert!(v2["page"]["next_cursor"].is_null());

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 5 : POST /notifications/:id/read est idempotent (#3884) ─────────────
// Régression #3884 : relire une notification déjà lue réécrivait read_at à
// now(), perdant l'horodatage de première lecture.

#[tokio::test]
async fn notification_mark_read_is_idempotent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-idempotent+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    let notif_id = insert_notification(&app_db, user_id, "rdv", "Votre RDV", false).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let uri = format!("/v1/notifications/{}/read", notif_id);

    let r1 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&uri)
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r1.status(), StatusCode::OK);
    let body1 = axum::body::to_bytes(r1.into_body(), usize::MAX)
        .await
        .unwrap();
    let v1: serde_json::Value = serde_json::from_slice(&body1).unwrap();
    let read_at_1 = v1["read_at"]
        .as_str()
        .expect("read_at doit être présent après le 1er marquage")
        .to_string();

    // Écart mesurable avant la relecture, pour distinguer un now() figé d'un
    // now() réécrit (résolution timestamptz largement < 50ms).
    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    let r2 = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&uri)
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r2.status(), StatusCode::OK);
    let body2 = axum::body::to_bytes(r2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&body2).unwrap();
    let read_at_2 = v2["read_at"].as_str().unwrap();

    assert_eq!(
        read_at_2, read_at_1,
        "read_at doit rester figé au premier marquage, pas réécrit à chaque relecture"
    );

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 6 : cursor indécodable → 422, pas silencieusement ignoré (#3874) ────
// Régression #3874 : ?cursor=garbage était avalé (.and_then transforme un
// cursor indécodable en "pas de cursor") → 200 avec la page 1, identique à
// l'absence de cursor. Un client paginant jusqu'à next_cursor==null bouclait
// indéfiniment sur un cursor corrompu/expiré.

#[tokio::test]
async fn notifications_malformed_cursor_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-badcursor+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    insert_notification(&app_db, user_id, "rdv", "Votre RDV", false).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    for bad_cursor in ["garbage", "1784011195493655|garbage", "abc|def"] {
        let response = app(state.clone())
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(format!("/v1/notifications?cursor={}", bad_cursor))
                    .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(
            response.status(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "cursor='{}' doit être rejeté (422), pas silencieusement ignoré",
            bad_cursor
        );
    }

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 6 : data/deep_link restitués (#3863) ─────────────────────────────────

#[tokio::test]
async fn notifications_list_restitutes_data_and_deep_link() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-data+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    let order_id = Uuid::new_v4();
    insert_notification_with_data(
        &app_db,
        user_id,
        "order_received",
        "Nouvelle commande reçue",
        json!({ "order_id": order_id, "status": "received" }),
    )
    .await;

    let entry_id = Uuid::new_v4();
    insert_notification_with_data(
        &app_db,
        user_id,
        "waiting_list_slot_offered",
        "Un créneau vous est proposé",
        json!({ "waiting_list_entry_id": entry_id, "proposed_at": "2026-07-25T10:00:00Z" }),
    )
    .await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let items = v["data"].as_array().unwrap();
    assert_eq!(items.len(), 2);

    // ORDER DESC : waiting_list_slot_offered inséré en dernier → items[0].
    let offered = &items[0];
    assert_eq!(offered["kind"], "waiting_list_slot_offered");
    assert_eq!(
        offered["data"]["waiting_list_entry_id"],
        entry_id.to_string()
    );
    assert_eq!(offered["data"]["proposed_at"], "2026-07-25T10:00:00Z");
    // Pas de page de détail patient pour ce kind (#3863) : pas de deep_link inventé.
    assert!(offered["deep_link"].is_null());

    let order = &items[1];
    assert_eq!(order["kind"], "order_received");
    assert_eq!(order["data"]["order_id"], order_id.to_string());
    assert_eq!(order["deep_link"], format!("/pharmacy/orders/{order_id}"));

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test : opt-out pro (#6278) — inapp_stock=false exclut stock_request_received ──
// Repro exacte de #6278 : `inapp_stock=false` persisté dans
// `user_notification_preference` (migration 0246) n'avait aucun effet, une
// notification `stock_request_received` restait visible et comptée dans
// `unread_count`. Vérifie aussi qu'une catégorie non opt-out (`inapp_devis`,
// resté à sa valeur par défaut) reste, elle, restituée normalement.

#[tokio::test]
async fn notifications_excludes_opted_out_pro_category() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("notif-optout+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO user_notification_preference (app_user_id, inapp_stock) VALUES ($1, false)",
    )
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    insert_notification(
        &app_db,
        user_id,
        "stock_request_received",
        "Nouvelle demande de stock",
        false,
    )
    .await;
    insert_notification(&app_db, user_id, "quote_signed", "Devis signé", false).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let items = v["data"].as_array().unwrap();
    // Seule la notification "quote_signed" (catégorie non opt-out) reste.
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["kind"], "quote_signed");
    // Le badge non-lus ne compte plus la notification opt-out.
    assert_eq!(v["page"]["unread_count"], 1);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
