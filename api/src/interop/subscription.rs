//! `/v1/interop/fhir/Subscription` — abonnements partenaires (rest-hook) et
//! livraison sortante HMAC des notifications de ressources FHIR (lot A7).
//!
//! ## Portée
//!
//! `criteria` est un simple filtre "type de ressource" (ex. `"Appointment"`),
//! PAS un critère de recherche FHIR complet (`Appointment?practitioner=...`) —
//! explicitement hors scope de ce lot. Seul `Appointment` émet des
//! notifications aujourd'hui (cf. `interop::appointment::create_appointment`
//! / `update_appointment_status`, qui appellent [`dispatch_notification`]).
//!
//! ## Secret partagé — pourquoi PAS argon2 (contrairement à `interop_client_secret`)
//!
//! `interop_client_secret` (lot A1) stocke un hash argon2 parce que Nubia ne
//! fait que **vérifier** ce secret (soumis par le partenaire à
//! `/oauth/token`) — un hash à sens unique suffit, il n'est jamais réutilisé.
//!
//! Le secret d'abonnement est l'inverse : c'est **Nubia qui doit signer**
//! (HMAC-SHA256) chaque livraison sortante avec ce secret exact. Le stocker
//! en hash argon2 (irréversible) rendrait toute signature impossible dès la
//! deuxième livraison — un bug de correction silencieux et grave, pas une
//! simplification acceptable.
//!
//! Choix retenu : le secret n'est **jamais persisté** (ni en clair, ni
//! chiffré). Il est re-dérivé à la demande via
//! `HMAC-SHA256(INTEROP_SIGNING_KEY, subscription.id)` — une fonction pure de
//! l'id (immuable) de l'abonnement et d'une clé serveur dédiée (jamais
//! réutilisée pour un autre usage : séparation des clés — `jwt_secret` ne
//! sert qu'aux JWT interop, cf. `interop::auth`). Le secret retourné une
//! seule fois au partenaire à la création EST cette valeur dérivée : stable
//! et recalculable indéfiniment côté serveur, sans jamais transiter par la
//! base. La colonne `secret_hash` (nom imposé par le schéma du lot, cf.
//! migration 0149) stocke un hash argon2 de ce secret dérivé, à titre
//! défensif/audit uniquement — jamais lu sur le chemin de signature.
//!
//! `core-crypto` (chiffrement d'enveloppe KMS) dispose désormais d'une
//! implémentation réelle, mais n'est délibérément PAS utilisé ici : la
//! dérivation HMAC ci-dessus est stateless (aucun secret persisté à faire
//! survivre à une rotation de clé maître KMS) et plus simple que de gérer
//! un `key_context`/`key_ref` pour une valeur qui n'a jamais besoin d'être
//! stockée. Le chiffrement d'enveloppe reste pertinent pour les colonnes
//! `*_ciphertext` qui, elles, doivent être persistées (cf. `docs/05` §3).
//!
//! ## Raccourci assumé — livraison synchrone best-effort
//!
//! Aucune implémentation "réelle" (non-stub) de `JobDispatcher` n'existe dans
//! ce dépôt (`grep -rn "impl JobDispatcher"` ne renvoie que
//! `StubJobDispatcher`, cf. `api/src/lib.rs`) — l'intégration apalis/Redis
//! reste à l'état de commentaire ("swappable (stub en test, apalis en
//! prod)") depuis le lot A1. Câbler un vrai worker apalis (connexion Redis,
//! boucle de consommation, retry) pour cette seule tranche serait un
//! chantier disproportionné par rapport au reste du lot.
//!
//! On prend donc le raccourci explicitement autorisé par la tâche :
//! [`dispatch_notification`] appelle `dispatcher.enqueue_interop_notification`
//! (hook inerte aujourd'hui — posé pour le jour où un vrai dispatcher
//! existera) PUIS exécute elle-même, de façon synchrone et best-effort, la
//! recherche des abonnements actifs + POST signé + écriture
//! `interop_delivery`. `next_attempt_at` est renseigné pour un futur worker
//! de retry — **aucun consommateur de ce champ n'existe dans cette
//! tranche** : un échec de livraison reste en statut `failed` tant qu'aucun
//! worker n'est câblé pour le reconsommer.

use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Extension, Json,
};
use core_tenancy::{with_tenant, TenancyError};
use hmac::{Hmac, Mac};
use integrations_interop::{hash_secret, Scope};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::Sha256;
use uuid::Uuid;

use crate::{
    interop::{
        appointment::FhirError,
        auth::{require_scope, InteropClaims},
    },
    AppState, InteropSigningKey, JobDispatcher,
};

type HmacSha256 = Hmac<Sha256>;

/// Toute erreur de transaction tenant est traitée fail-closed : jamais de
/// détail DB exposé au partenaire. Copie volontaire du helper homonyme de
/// `appointment.rs` (privé à son module, cf. commentaire de duplication
/// assumée dans ce fichier).
fn internal_from_tenancy(_: TenancyError) -> FhirError {
    FhirError::Internal
}

// ─────────────────────────────────────────────────────────────────────────
// Dérivation du secret de signature — cf. doc de module.
// ─────────────────────────────────────────────────────────────────────────

/// Dérive de façon déterministe le secret partagé d'un abonnement à partir
/// de la clé serveur `INTEROP_SIGNING_KEY` et de l'id (immuable) de
/// l'abonnement. Jamais stocké — recalculable à l'identique à chaque
/// livraison.
fn derive_subscription_secret(signing_key: &str, subscription_id: Uuid) -> Result<String, ()> {
    let mut mac = HmacSha256::new_from_slice(signing_key.as_bytes()).map_err(|_| ())?;
    mac.update(subscription_id.to_string().as_bytes());
    Ok(hex::encode(mac.finalize().into_bytes()))
}

/// Signe un payload de livraison HMAC-SHA256/hex — même construction que
/// `webhooks::stripe::verify_stripe_signature`, en sens inverse (signature
/// plutôt que vérification).
fn sign_payload(secret: &str, body: &[u8]) -> Result<String, ()> {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).map_err(|_| ())?;
    mac.update(body);
    Ok(hex::encode(mac.finalize().into_bytes()))
}

// ─────────────────────────────────────────────────────────────────────────
// Représentation JSON FHIR minimale
// ─────────────────────────────────────────────────────────────────────────

#[derive(Debug, sqlx::FromRow)]
struct SubscriptionRow {
    id: Uuid,
    criteria: String,
    endpoint_url: String,
    status: String,
}

/// `secret` n'est fourni qu'à la création (`POST`) — jamais sur un `GET`.
fn subscription_to_fhir(row: &SubscriptionRow, secret: Option<&str>) -> Value {
    let mut body = json!({
        "resourceType": "Subscription",
        "id": row.id,
        "status": row.status,
        "criteria": row.criteria,
        "channel": {
            "type": "rest-hook",
            "endpoint": row.endpoint_url,
        },
    });
    if let Some(secret) = secret {
        // Extension Nubia (pas un champ FHIR core) : secret HMAC en clair,
        // présent une seule fois sur la réponse de création.
        body["secret"] = json!(secret);
    }
    body
}

// ─────────────────────────────────────────────────────────────────────────
// POST /v1/interop/fhir/Subscription
// ─────────────────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
pub struct FhirSubscriptionChannelIn {
    #[serde(rename = "type")]
    pub channel_type: String,
    pub endpoint: String,
}

#[derive(Debug, Deserialize)]
pub struct FhirSubscriptionIn {
    pub criteria: String,
    pub channel: FhirSubscriptionChannelIn,
}

/// `POST /v1/interop/fhir/Subscription` — enregistre un abonnement rest-hook.
///
/// Scope `subscriptions:write` requis. `criteria` : filtre simple sur le
/// type de ressource (ex. `"Appointment"`) — pas de FHIR search complet
/// (hors scope de ce lot, cf. doc de module). `channel.type` doit valoir
/// `"rest-hook"` (seul mode supporté) et `channel.endpoint` une URL
/// `https://` (on ne notifie jamais un endpoint partenaire en clair).
/// Retourne le secret HMAC généré **une seule fois** — jamais ré-exposé
/// ensuite (cf. doc de module pour le choix de non-persistance).
pub async fn create_subscription(
    State(state): State<AppState>,
    Extension(InteropSigningKey(signing_key)): Extension<InteropSigningKey>,
    claims: InteropClaims,
    Json(body): Json<FhirSubscriptionIn>,
) -> Result<(StatusCode, Json<Value>), FhirError> {
    require_scope(&claims, Scope::SubscriptionsWrite).map_err(|_| FhirError::Forbidden)?;

    let criteria = body.criteria.trim();
    if criteria.is_empty() {
        return Err(FhirError::BadRequest("criteria requis".to_string()));
    }
    if body.channel.channel_type != "rest-hook" {
        return Err(FhirError::BadRequest(
            "channel.type doit être 'rest-hook' (seul mode supporté)".to_string(),
        ));
    }
    let endpoint_url = body.channel.endpoint.trim();
    if !endpoint_url.starts_with("https://") {
        return Err(FhirError::BadRequest(
            "channel.endpoint doit être une URL https://".to_string(),
        ));
    }
    if signing_key.is_empty() {
        // Fail-closed : une clé de signature vide rendrait le secret généré
        // devinable (HMAC(clé vide, id) est calculable publiquement dès que
        // l'id est connu) — même garde-fou que webhooks::stripe pour un
        // secret vide.
        return Err(FhirError::Internal);
    }

    let subscription_id = Uuid::new_v4();
    let secret = derive_subscription_secret(&signing_key, subscription_id)
        .map_err(|_| FhirError::Internal)?;
    let secret_hash = hash_secret(&secret).map_err(|_| FhirError::Internal)?;

    let cabinet_id = claims.cabinet_id;
    let criteria_owned = criteria.to_string();
    let endpoint_owned = endpoint_url.to_string();

    let row: SubscriptionRow = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let row = sqlx::query_as::<_, SubscriptionRow>(
            "INSERT INTO interop_subscription (id, cabinet_id, criteria, endpoint_url, secret_hash, status) \
             VALUES ($1, $2, $3, $4, $5, 'active') \
             RETURNING id, criteria, endpoint_url, status",
        )
        .bind(subscription_id)
        .bind(cabinet_id)
        .bind(&criteria_owned)
        .bind(&endpoint_owned)
        .bind(&secret_hash)
        .fetch_one(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(row)
    })
    .await
    .map_err(internal_from_tenancy)?;

    Ok((
        StatusCode::CREATED,
        Json(subscription_to_fhir(&row, Some(&secret))),
    ))
}

// ─────────────────────────────────────────────────────────────────────────
// GET /v1/interop/fhir/Subscription/:id
// ─────────────────────────────────────────────────────────────────────────

/// `GET /v1/interop/fhir/Subscription/:id` — lecture (jamais le secret).
///
/// Réutilise le scope `subscriptions:write` : aucun scope
/// `subscriptions:read` dédié n'existe (cf. `integrations_interop::Scope`,
/// périmètre figé à 6 valeurs pour ce lot) — ajouter une variante `:read`
/// rien que pour ce `GET` a été jugé disproportionné pour cette tranche.
pub async fn get_subscription(
    State(state): State<AppState>,
    claims: InteropClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::SubscriptionsWrite).map_err(|_| FhirError::Forbidden)?;

    let cabinet_id = claims.cabinet_id;
    let row: Option<SubscriptionRow> =
        with_tenant(&state.db, cabinet_id, move |mut tx| async move {
            let row = sqlx::query_as::<_, SubscriptionRow>(
                "SELECT id, criteria, endpoint_url, status \
             FROM interop_subscription WHERE id = $1 AND cabinet_id = $2",
            )
            .bind(id)
            .bind(cabinet_id)
            .fetch_optional(&mut *tx)
            .await?;
            Ok(row)
        })
        .await
        .map_err(internal_from_tenancy)?;

    let row = row.ok_or_else(|| {
        FhirError::NotFound("Subscription introuvable pour ce cabinet".to_string())
    })?;
    Ok(Json(subscription_to_fhir(&row, None)))
}

// ─────────────────────────────────────────────────────────────────────────
// Livraison sortante — appelé depuis appointment.rs après commit.
// ─────────────────────────────────────────────────────────────────────────

#[derive(Debug, sqlx::FromRow)]
struct ActiveSubscriptionRow {
    id: Uuid,
    endpoint_url: String,
}

/// Backoff (secondes) avant une prochaine tentative — **informatif
/// uniquement** dans cette tranche : aucun worker ne consomme
/// `next_attempt_at` pour l'instant (cf. doc de module). Exponentiel,
/// plafonné à 1h, capé à 6 tentatives conceptuelles.
fn backoff_seconds(attempts: i32) -> i64 {
    let capped = attempts.clamp(1, 6);
    (60_i64.saturating_mul(1_i64 << (capped - 1))).min(3600)
}

/// Point d'entrée appelé après commit d'une écriture FHIR (`create_appointment`,
/// `update_appointment_status`). Fire-and-forget vis-à-vis de l'appelant :
/// n'échoue jamais la requête d'origine (déjà commitée) — toute erreur est
/// loguée puis avalée. Cf. doc de module pour le raccourci "synchrone
/// best-effort" assumé (pas de worker asynchrone dans cette tranche).
pub async fn dispatch_notification(
    state: &AppState,
    dispatcher: &Arc<dyn JobDispatcher>,
    signing_key: &str,
    cabinet_id: Uuid,
    resource_type: &str,
    resource_id: Uuid,
) {
    // Hook posé pour un futur vrai dispatcher apalis — no-op aujourd'hui
    // (StubJobDispatcher, seule implémentation existante dans ce dépôt).
    dispatcher.enqueue_interop_notification(cabinet_id, resource_type, resource_id);

    if signing_key.is_empty() {
        tracing::warn!(
            cabinet_id = %cabinet_id,
            resource_type = %resource_type,
            "INTEROP_SIGNING_KEY absente — livraison interop ignorée (fail-closed)"
        );
        return;
    }

    let subscriptions: Result<Vec<ActiveSubscriptionRow>, TenancyError> =
        with_tenant(&state.db, cabinet_id, move |mut tx| async move {
            let rows = sqlx::query_as::<_, ActiveSubscriptionRow>(
                "SELECT id, endpoint_url FROM interop_subscription \
                 WHERE cabinet_id = $1 AND criteria = $2 AND status = 'active'",
            )
            .bind(cabinet_id)
            .bind(resource_type)
            .fetch_all(&mut *tx)
            .await?;
            Ok(rows)
        })
        .await;

    let subscriptions = match subscriptions {
        Ok(rows) => rows,
        Err(e) => {
            tracing::warn!(
                cabinet_id = %cabinet_id,
                error = ?e,
                "lookup interop_subscription échoué — livraison interop abandonnée"
            );
            return;
        }
    };

    for sub in subscriptions {
        deliver_one(
            state,
            signing_key,
            cabinet_id,
            sub,
            resource_type,
            resource_id,
        )
        .await;
    }
}

/// Tente une livraison unique (pas de retry synchrone : la boucle appelante
/// itère une fois par abonnement, un seul essai HTTP par abonnement et par
/// événement). Enregistre systématiquement le résultat dans `interop_delivery`.
async fn deliver_one(
    state: &AppState,
    signing_key: &str,
    cabinet_id: Uuid,
    sub: ActiveSubscriptionRow,
    resource_type: &str,
    resource_id: Uuid,
) {
    // Enveloppe minimale volontaire : pas de contenu de la ressource elle-même
    // (le partenaire la récupère via son propre token, GET /fhir/<Type>/:id).
    let envelope = json!({
        "resourceType": resource_type,
        "id": resource_id,
        "cabinet_id": cabinet_id,
    });
    let body_bytes = match serde_json::to_vec(&envelope) {
        Ok(b) => b,
        Err(_) => return,
    };

    let signature = derive_subscription_secret(signing_key, sub.id)
        .and_then(|secret| sign_payload(&secret, &body_bytes));

    let (status, last_error): (&str, Option<String>) = match signature {
        Err(_) => (
            "failed",
            Some("échec de calcul de la signature HMAC".to_string()),
        ),
        Ok(signature) => {
            let client = reqwest::Client::new();
            let result = client
                .post(&sub.endpoint_url)
                .header("Content-Type", "application/json")
                .header("X-Nubia-Signature", format!("sha256={signature}"))
                .timeout(std::time::Duration::from_secs(5))
                .body(body_bytes)
                .send()
                .await;
            match result {
                Ok(resp) if resp.status().is_success() => ("delivered", None),
                Ok(resp) => ("failed", Some(format!("HTTP {}", resp.status().as_u16()))),
                Err(e) => ("failed", Some(e.to_string())),
            }
        }
    };

    let next_attempt_at = if status == "failed" {
        Some(chrono::Utc::now() + chrono::Duration::seconds(backoff_seconds(1)))
    } else {
        None
    };

    let insert = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        sqlx::query(
            "INSERT INTO interop_delivery \
             (subscription_id, resource_type, resource_id, status, attempts, last_error, next_attempt_at) \
             VALUES ($1, $2, $3, $4, 1, $5, $6)",
        )
        .bind(sub.id)
        .bind(resource_type)
        .bind(resource_id)
        .bind(status)
        .bind(&last_error)
        .bind(next_attempt_at)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    })
    .await;

    if let Err(e) = insert {
        tracing::warn!(
            subscription_id = %sub.id,
            error = ?e,
            "écriture interop_delivery échouée"
        );
    }
}

// ─────────────────────────────────────────────────────────────────────────
// Tests unitaires purs (pas de DB requise)
// ─────────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derive_subscription_secret_is_deterministic() {
        let sub_id = Uuid::new_v4();
        let a = derive_subscription_secret("server-key", sub_id).unwrap();
        let b = derive_subscription_secret("server-key", sub_id).unwrap();
        assert_eq!(a, b, "même clé + même id => même secret dérivé");
    }

    #[test]
    fn derive_subscription_secret_differs_per_subscription() {
        let a = derive_subscription_secret("server-key", Uuid::new_v4()).unwrap();
        let b = derive_subscription_secret("server-key", Uuid::new_v4()).unwrap();
        assert_ne!(
            a, b,
            "deux abonnements distincts doivent avoir des secrets distincts"
        );
    }

    #[test]
    fn derive_subscription_secret_differs_per_key() {
        let sub_id = Uuid::new_v4();
        let a = derive_subscription_secret("server-key-1", sub_id).unwrap();
        let b = derive_subscription_secret("server-key-2", sub_id).unwrap();
        assert_ne!(
            a, b,
            "une clé serveur différente doit dériver un secret différent"
        );
    }

    #[test]
    fn sign_payload_roundtrip_is_stable() {
        let secret = "shared-secret";
        let body = b"{\"resourceType\":\"Appointment\",\"id\":\"abc\"}";
        let sig1 = sign_payload(secret, body).unwrap();
        let sig2 = sign_payload(secret, body).unwrap();
        assert_eq!(sig1, sig2);
        assert_ne!(sig1, sign_payload("other-secret", body).unwrap());
    }

    #[test]
    fn backoff_seconds_grows_and_caps() {
        assert_eq!(backoff_seconds(1), 60);
        assert_eq!(backoff_seconds(2), 120);
        assert_eq!(backoff_seconds(3), 240);
        assert!(backoff_seconds(6) <= 3600);
        assert!(
            backoff_seconds(20) <= 3600,
            "doit rester plafonné même au-delà de 6"
        );
    }

    #[test]
    fn backoff_seconds_never_negative_or_zero() {
        for attempts in 0..10 {
            assert!(backoff_seconds(attempts) > 0);
        }
    }
}
