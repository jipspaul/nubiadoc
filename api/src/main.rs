use std::net::SocketAddr;
use std::sync::Arc;

use nubia_api::hl7v2::listener::{self, Hl7v2ListenerStatus};
use nubia_api::{
    run_dispatch_loop, run_quote_relance_loop, run_visit_offer_expiry_loop, AppState, BrevoMailer,
    FcmJobDispatcher, LocalStorageSigner, ScalewayStorageSigner, StorageSigner, StubJobDispatcher,
    TwilioSmsSender, YousignClient,
};
use sqlx::PgPool;

/// `ScalewayStorageSigner` dès que `SCW_ACCESS_KEY`/`SCW_SECRET_KEY`/`SCW_BUCKET`
/// sont toutes renseignées (#4717) ; sinon `LocalStorageSigner` (#6425 —
/// récidive de #6250 : le plombage CI -> conteneur de ces variables ne
/// suffit pas tant qu'aucun compte Scaleway n'est réellement provisionné
/// côté secrets Forgejo, et `ScalewayStorageSigner::from_env()` reste alors
/// `None` indéfiniment -> 502 upstream_unavailable sur 100% des documents).
fn storage_signer() -> std::sync::Arc<dyn StorageSigner> {
    let scw_configured = ["SCW_ACCESS_KEY", "SCW_SECRET_KEY", "SCW_BUCKET"]
        .iter()
        .all(|key| std::env::var(key).map(|v| !v.is_empty()).unwrap_or(false));

    if scw_configured {
        std::sync::Arc::new(ScalewayStorageSigner::from_env())
    } else {
        std::sync::Arc::new(LocalStorageSigner::from_env())
    }
}

#[tokio::main]
async fn main() {
    let pool =
        PgPool::connect(&std::env::var("APP_DATABASE_URL").expect("APP_DATABASE_URL must be set"))
            .await
            .expect("failed to connect to database");

    let state = AppState {
        db: pool.clone(),
        jwt_secret: std::env::var("JWT_SECRET").unwrap_or_default(),
        // BrevoMailer en prod (#4035) ; StubMailer reste utilisé par les
        // tests d'intégration, qui construisent leur propre AppState.
        mailer: Arc::new(BrevoMailer::from_env()),
    };

    let port: u16 = std::env::var("APP_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(3000);
    let bind = format!("0.0.0.0:{port}");
    let listener = tokio::net::TcpListener::bind(&bind).await.unwrap();
    println!("nubia-api listening on {bind}");

    // Lot B10 : le listener MLLP tourne comme second tokio::task dans le même
    // binaire (ADR-002/ADR-012 : monolithe modulaire, pas un second
    // conteneur). Désactivé silencieusement si MLLP_TLS_CERT_PATH n'est pas
    // configuré (cf. hl7v2::listener::serve) — pas de blocage du démarrage
    // HTTP sur une fonctionnalité encore optionnelle en production.
    let mllp_status = Hl7v2ListenerStatus::default();
    let mllp_task = listener::serve(pool, mllp_status.clone());

    // `tokio::spawn` (et non `tokio::select!`) : le listener MLLP retourne
    // quasi immédiatement quand sa config est absente/invalide (cf. doc de
    // `listener::serve`), et `select!` fait alors avorter la branche HTTP
    // dès que la branche MLLP se termine — tuant le process quelques
    // secondes après le boot (postmortem déploiement LXC : nubia-api
    // Exited(0) en boucle malgré "listening on ..." dans les logs).
    tokio::spawn(async move {
        mllp_task.await;
        eprintln!("listener MLLP arrêté (configuration absente ou invalide)");
    });

    // Worker de dispatch des rappels RDV (#4034, canal sms #4036) : même
    // pattern que le listener MLLP ci-dessus (tokio::spawn dans le même
    // binaire, ADR-002/ADR-012 — pas de job queue apalis dans ce dépôt à ce
    // jour, cf. doc de module reminder_dispatch.rs). FcmJobDispatcher (#6321)
    // décore StubJobDispatcher : push FCM réel si FIREBASE_SERVICE_ACCOUNT est
    // configuré, sinon fallback silencieux identique à avant (stub pur).
    // TwilioSmsSender en prod (#4036), cf. sa doc de module pour le choix du
    // provider.
    const REMINDER_DISPATCH_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60);
    tokio::spawn(run_dispatch_loop(
        state.db.clone(),
        std::sync::Arc::new(FcmJobDispatcher::new(
            std::sync::Arc::new(StubJobDispatcher),
            state.db.clone(),
        )),
        std::sync::Arc::new(TwilioSmsSender::from_env()),
        REMINDER_DISPATCH_INTERVAL,
    ));

    // Worker de relance des devis en attente de signature (#4126) : même
    // pattern tokio::spawn que le dispatch de rappels ci-dessus. Intervalle
    // large (contrairement aux rappels RDV, une relance J+3/J+7 tolère
    // largement un passage toutes les 6h — pas besoin d'un balayage minute
    // par minute sur une fenêtre de plusieurs jours).
    const QUOTE_RELANCE_INTERVAL: std::time::Duration = std::time::Duration::from_secs(6 * 3600);
    tokio::spawn(run_quote_relance_loop(
        state.db.clone(),
        QUOTE_RELANCE_INTERVAL,
    ));

    // Worker de résolution des offres de visite infirmière expirées (#5730) :
    // même pattern tokio::spawn que les workers ci-dessus. Intervalle court
    // (contrairement à la relance devis) car le TTL par défaut d'une offre
    // (`offer_visit_to_nurses`, migration 0234) est de 5 minutes — un
    // patient dont la seule infirmière proche ne répond jamais ne doit pas
    // attendre des heures avant de recevoir le signal "aucune infirmière
    // disponible".
    const VISIT_OFFER_EXPIRY_INTERVAL: std::time::Duration = std::time::Duration::from_secs(30);
    tokio::spawn(run_visit_offer_expiry_loop(
        state.db.clone(),
        std::sync::Arc::new(FcmJobDispatcher::new(
            std::sync::Arc::new(StubJobDispatcher),
            state.db.clone(),
        )),
        VISIT_OFFER_EXPIRY_INTERVAL,
    ));

    // Pages SSR publiques du tunnel de réservation (#5356) : mêmes routes
    // qu'avant (ce ne sont pas des routes d'API, pas de préfixe `/v1/...`),
    // mais désormais mergées dans le routeur HTTP servi sur `APP_PORT` au
    // lieu d'un routeur/port séparé (`WEB_TUNNEL_PORT`) — #5628 : ce second
    // port n'était raccordé à AUCUN nom de domaine en production (le Caddy
    // réel de l'hôte, hors LXC, se configure à la main via
    // `infra/deploy/Caddyfile.snippet` — jamais mis à jour pour ce port), le
    // rendant 100 % injoignable malgré un code fonctionnellement correct.
    // `api.<domaine>` proxie déjà TOUT le port `APP_PORT` sans filtre de
    // chemin (cf. Caddyfile.snippet) : merger ici rend ces pages joignables
    // immédiatement, sans aucune action manuelle côté hôte. Pas de collision
    // possible : `/v1/...` a un préfixe fixe (jamais capturé par les
    // catch-all `/:slug` ou `/:query_slug/:locality_slug` du tunnel, qui
    // exigent respectivement exactement 1 et 2 segments).
    let http_task = axum::serve(
        listener,
        app_with_hl7v2_status(state.clone(), mllp_status)
            .merge(nubia_api::web_tunnel::router(state))
            .into_make_service_with_connect_info::<SocketAddr>(),
    );

    if let Err(e) = http_task.await {
        eprintln!("serveur HTTP arrêté avec une erreur : {e}");
    }
}

/// Ajoute `GET /v1/interop/hl7v2/health` au routeur Axum standard : le
/// healthcheck HTTP existant (`/v1/health`) ne couvre que le serveur Axum,
/// pas le second listener TCP MLLP (lot B10) — route dédiée pour ne pas
/// modifier la signature de `build_router`/`app` (utilisée par de nombreux
/// tests d'intégration existants).
fn app_with_hl7v2_status(state: AppState, mllp_status: Hl7v2ListenerStatus) -> axum::Router {
    // YousignClient en prod (#4064) ; ScalewayStorageSigner en prod (#4717 —
    // remplace le StubStorageSigner câblé en dur qui générait des URL vers
    // le domaine fantôme storage.example.com). StubQuoteSignatureClient/
    // StubStorageSigner restent utilisés par app(state)/les tests
    // d'intégration qui construisent leur propre routeur.
    // Hub WS créé ICI (et non dans le builder) pour être partagé avec le
    // `WsPushDispatcher` : les notifications insérées sont poussées en temps
    // réel sur le canal `notifications` des sockets ouvertes, EN PLUS du push
    // FCM réel (`FcmJobDispatcher`, #6321) — la socket couvre l'app vivante,
    // FCM couvre l'app tuée/en arrière-plan.
    let hub = std::sync::Arc::new(nubia_api::WsHub::new());
    let dispatcher = std::sync::Arc::new(FcmJobDispatcher::new(
        std::sync::Arc::new(nubia_api::realtime_push_dispatcher(
            hub.clone(),
            state.db.clone(),
        )),
        state.db.clone(),
    ));
    nubia_api::app_prod(
        state,
        std::sync::Arc::new(YousignClient::from_env()),
        storage_signer(),
        hub,
        dispatcher,
    )
    .route("/v1/interop/hl7v2/health", axum::routing::get(hl7v2_health))
    .layer(axum::Extension(mllp_status))
}

async fn hl7v2_health(
    axum::Extension(status): axum::Extension<Hl7v2ListenerStatus>,
) -> impl axum::response::IntoResponse {
    if status.is_ready() {
        (axum::http::StatusCode::OK, "ok")
    } else {
        (axum::http::StatusCode::SERVICE_UNAVAILABLE, "not_ready")
    }
}
