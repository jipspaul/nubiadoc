//! Handlers `/v1/cabinet/messages` — messagerie interne d'équipe (staff↔staff),
//! distincte de la messagerie patient (`cabinet_messaging.rs`, table `conversation`/
//! `message`). Table `cabinet_messages` (migration 0106), jusqu'ici sans route
//! API (#4156, différentiel Desmos [D]).
//!
//! Fil unique par cabinet (pas de conversations/destinataires — tout le
//! staff voit tous les messages), cohérent avec le schéma minimal de la
//! table (`sender_id`, `body`, pas de `recipient_id`/`thread_id`).

use std::collections::HashMap;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::{postgres::PgRow, Row};
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Libellé humain (design-v2) pour un `cabinet_membership.role` (#6543).
/// `None` pour un rôle inconnu/absent (sender ayant quitté le cabinet) :
/// le front n'affiche alors pas de pastille.
fn role_label(role: &str) -> &'static str {
    match role {
        "practitioner" | "doctor" => "Praticien",
        "secretary" => "Secrétaire",
        "manager" => "Manager",
        "admin" => "Administrateur",
        _ => "Membre du cabinet",
    }
}

/// Référence à un objet du produit citée par un message (#5131/#8208,
/// encadré 3 « Citer un objet du produit » de la maquette, bloc aside
/// « Éléments cités aujourd'hui » et carte en ligne dans le fil).
#[derive(Serialize)]
pub struct CabinetTeamMessageReferenceItem {
    #[serde(rename = "type")]
    pub kind: String,
    pub target_id: Uuid,
    pub title: String,
    pub subtitle: String,
}

/// Types de référence reconnus (#8208) — alignés sur
/// `CabinetTeamMessageReferenceType` côté front
/// (`cabinet_team_messages_dto.dart`).
const ALLOWED_REFERENCE_TYPES: &[&str] = &[
    "patient",
    "devis",
    "lab_work_order",
    "stock_request",
    "agenda_slot",
];

/// Un message interne d'équipe.
#[derive(Serialize)]
pub struct CabinetTeamMessageItem {
    pub id: Uuid,
    pub sender_id: Uuid,
    /// `provider.display_name` du praticien émetteur, sinon prénom/nom
    /// (`app_user`, #6543 — RLS self-only contournée via `current_user_id`
    /// positionné par sender comme dans `get_cabinet_members`), sinon
    /// `"Membre du cabinet"`.
    pub sender_name: String,
    /// Libellé de rôle (#6543, pastille design-v2) — `None` si le sender n'a
    /// plus de `cabinet_membership` actif dans ce cabinet.
    pub sender_role: Option<String>,
    pub body: String,
    pub created_at: String,
    /// Épinglage (#5130/#8181) — posé via `POST .../:id/pin`.
    pub pinned: bool,
    pub pinned_by: Option<Uuid>,
    pub pinned_at: Option<String>,
    /// Objet produit cité (#5131/#8208) — `None` si aucun n'a été joint à
    /// l'envoi.
    pub reference: Option<CabinetTeamMessageReferenceItem>,
    /// Noms des membres mentionnés (`@Nom`) dans `body` (#5129/#8208),
    /// dérivés de `body` à la lecture (même pattern que le parsing
    /// d'affichage front, `mention_text_parser.dart`) — aucune colonne
    /// dédiée, `body` reste l'unique source de vérité.
    pub mentions: Vec<String>,
}

/// Extrait les mentions `@Nom` de `body` (#8208), même sémantique que le
/// `RegExp(r'@[\p{L}\p{N}_]+')` front (`mention_text_parser.dart`) : une
/// mention est un `@` suivi d'au moins un caractère alphanumérique/`_`, le
/// `@` seul (ou répété) n'en formant aucune.
fn extract_mentions(body: &str) -> Vec<String> {
    let mut mentions = Vec::new();
    let mut chars = body.chars().peekable();
    while let Some(c) = chars.next() {
        if c != '@' {
            continue;
        }
        let mut name = String::new();
        while let Some(&next) = chars.peek() {
            if next.is_alphanumeric() || next == '_' {
                name.push(next);
                chars.next();
            } else {
                break;
            }
        }
        if !name.is_empty() {
            mentions.push(name);
        }
    }
    mentions
}

/// Métadonnées de pagination (même forme que `NotificationsPage`,
/// `api/src/notifications.rs`).
#[derive(Serialize)]
pub struct CabinetTeamMessagesPage {
    pub next_cursor: Option<String>,
}

/// Réponse de `GET /v1/cabinet/messages`.
#[derive(Serialize)]
pub struct ListCabinetTeamMessagesResponse {
    pub data: Vec<CabinetTeamMessageItem>,
    pub page: CabinetTeamMessagesPage,
}

/// Query de `GET /v1/cabinet/messages`.
#[derive(Deserialize)]
pub struct ListCabinetTeamMessagesQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

fn encode_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/cabinet/messages` — fil des messages internes du cabinet (#4156).
///
/// Tout membre du staff (`ProSecretaryPlusClaims` : secretary/practitioner/
/// admin/manager) — patient → 403. `cabinet_id` extrait du JWT, jamais du
/// path/query (invariant tenancy). RLS tenant-scoped via
/// `app.current_cabinet_id`.
///
/// #6921 : la page sert les messages les plus RÉCENTS (requête triée
/// `created_at DESC, id DESC` + `LIMIT`, comme `GET /v1/notifications`),
/// puis les ré-ordonne en chronologique croissant (`data`) — c'est l'ordre
/// déjà consommé tel quel par le front (`_MessagesList`, aucun changement
/// requis côté client). `cursor` (`page.next_cursor`) permet de remonter
/// vers les messages plus anciens ; sans lui, un fil de plus de `limit`
/// messages ne figeait plus jamais sur ses 200 plus anciens messages (tri
/// `ASC` d'origine) en rendant tout nouveau message inatteignable.
/// `limit` 1..=200 (défaut 100).
pub async fn list_cabinet_team_messages(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(query): Query<ListCabinetTeamMessagesQuery>,
) -> Result<Json<ListCabinetTeamMessagesResponse>, AppError> {
    let limit = query.limit.unwrap_or(100).clamp(1, 200);
    // `cursor` absent → première page (plus récents). `cursor` présent mais
    // indécodable → 422 plutôt que silencieusement ignoré (même invariant
    // que `list_notifications`, #3874).
    let cursor = match query.cursor.as_deref() {
        Some(s) => Some(decode_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cursor_clause = if cursor.is_some() {
        " AND (cm.created_at < $3 OR (cm.created_at = $3 AND cm.id < $4))"
    } else {
        ""
    };

    // `provider.display_name` couvre les praticiens ; `cabinet_membership`
    // donne le rôle pour la pastille (#6543). Le nom des non-praticiens
    // (secrétariat/admin) est résolu ensuite via `app_user`, ligne par ligne
    // (cf. boucle ci-dessous).
    let sql = format!(
        "SELECT cm.id, cm.sender_id, cm.body, cm.created_at, \
                cm.pinned, cm.pinned_by, cm.pinned_at, \
                cm.reference_type, cm.reference_target_id, \
                cm.reference_title, cm.reference_subtitle, \
                prov.display_name AS provider_display_name, \
                cmb.role AS sender_role \
         FROM cabinet_messages cm \
         LEFT JOIN practitioner p ON p.user_id = cm.sender_id AND p.cabinet_id = cm.cabinet_id \
         LEFT JOIN provider prov ON prov.practitioner_id = p.id AND prov.cabinet_id = cm.cabinet_id \
         LEFT JOIN cabinet_membership cmb ON cmb.user_id = cm.sender_id AND cmb.cabinet_id = cm.cabinet_id \
         WHERE cm.cabinet_id = $1 AND cm.deleted_at IS NULL \
         {cursor_clause} \
         ORDER BY cm.created_at DESC, cm.id DESC \
         LIMIT $2"
    );

    // On demande une ligne de plus que `limit` pour savoir s'il reste des
    // messages plus anciens (`next_cursor`), même pattern que `notifications.rs`.
    let fetch_limit = limit + 1;

    let mut rows = match cursor {
        Some((cursor_ts, cursor_id)) => sqlx::query(&sql)
            .bind(claims.cabinet_id)
            .bind(fetch_limit)
            .bind(cursor_ts)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        None => sqlx::query(&sql)
            .bind(claims.cabinet_id)
            .bind(fetch_limit)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
    };

    let has_more = rows.len() > limit as usize;
    rows.truncate(limit as usize);

    let next_cursor = if has_more {
        let oldest = rows.last().ok_or(AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> = oldest
            .try_get("created_at")
            .map_err(|_| AppError::Internal)?;
        let id: Uuid = oldest.try_get("id").map_err(|_| AppError::Internal)?;
        Some(encode_cursor(created_at, id))
    } else {
        None
    };

    // Les lignes arrivent en `DESC` (plus récent d'abord, pour la pagination) ;
    // le fil s'affiche en chronologique croissant (cf. docstring ci-dessus).
    rows.reverse();

    let resolved_names = resolve_sender_names(&mut tx, &rows).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(|r| build_message_item(r, &resolved_names))
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(ListCabinetTeamMessagesResponse {
        data,
        page: CabinetTeamMessagesPage { next_cursor },
    }))
}

/// Résout `sender_id → nom affiché` pour un lot de lignes `cabinet_messages`,
/// partagé par [`list_cabinet_team_messages`] et
/// [`list_pinned_cabinet_team_messages`].
///
/// #4416/#6543 : `app_user` porte une RLS stricte self-only
/// (user_self_select, 0045_platform_rls.sql — `id = app.current_user_id`),
/// donc invisible pour tout sender autre que le viewer courant. Même
/// contournement que `get_cabinet_members` : on repositionne le GUC par
/// sender avant de lire son nom, avec un cache pour ne le faire qu'une fois
/// par auteur distinct du lot.
async fn resolve_sender_names(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    rows: &[PgRow],
) -> Result<HashMap<Uuid, Option<String>>, AppError> {
    let mut resolved_names: HashMap<Uuid, Option<String>> = HashMap::new();
    for sender_id in rows
        .iter()
        .map(|r| r.try_get::<Uuid, _>("sender_id"))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| AppError::Internal)?
    {
        if resolved_names.contains_key(&sender_id) {
            continue;
        }

        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(sender_id.to_string())
            .execute(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let user_row = sqlx::query("SELECT first_name, last_name FROM app_user WHERE id = $1")
            .bind(sender_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let name = user_row.and_then(|row| {
            let first_name: Option<String> = row.try_get("first_name").ok()?;
            let last_name: Option<String> = row.try_get("last_name").ok()?;
            let full_name = [first_name, last_name]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>()
                .join(" ");
            // Ne pas retenir l'e-mail comme nom (#6714) : `None` ici laisse
            // jouer le repli documenté "Membre du cabinet" (ligne ~178) au
            // lieu de court-circuiter avec une donnée d'identification que
            // le fil n'a pas à exposer à toute l'équipe.
            (!full_name.trim().is_empty()).then_some(full_name)
        });
        resolved_names.insert(sender_id, name);
    }

    Ok(resolved_names)
}

/// Mappe une ligne `cabinet_messages` (+ jointures) vers [`CabinetTeamMessageItem`],
/// partagé par [`list_cabinet_team_messages`] et
/// [`list_pinned_cabinet_team_messages`].
fn build_message_item(
    r: &PgRow,
    resolved_names: &HashMap<Uuid, Option<String>>,
) -> Result<CabinetTeamMessageItem, AppError> {
    let created_at: chrono::DateTime<chrono::Utc> =
        r.try_get("created_at").map_err(|_| AppError::Internal)?;
    let sender_id: Uuid = r.try_get("sender_id").map_err(|_| AppError::Internal)?;
    let provider_display_name: Option<String> = r
        .try_get("provider_display_name")
        .map_err(|_| AppError::Internal)?;
    let role: Option<String> = r.try_get("sender_role").map_err(|_| AppError::Internal)?;

    let sender_name = provider_display_name
        .or_else(|| resolved_names.get(&sender_id).cloned().flatten())
        .unwrap_or_else(|| "Membre du cabinet".to_string());

    let pinned_at: Option<chrono::DateTime<chrono::Utc>> =
        r.try_get("pinned_at").map_err(|_| AppError::Internal)?;

    let body: String = r.try_get("body").map_err(|_| AppError::Internal)?;
    let mentions = extract_mentions(&body);

    let reference_type: Option<String> = r
        .try_get("reference_type")
        .map_err(|_| AppError::Internal)?;
    let reference = match reference_type {
        Some(kind) => Some(CabinetTeamMessageReferenceItem {
            kind,
            target_id: r
                .try_get("reference_target_id")
                .map_err(|_| AppError::Internal)?,
            title: r
                .try_get("reference_title")
                .map_err(|_| AppError::Internal)?,
            subtitle: r
                .try_get("reference_subtitle")
                .map_err(|_| AppError::Internal)?,
        }),
        None => None,
    };

    Ok(CabinetTeamMessageItem {
        id: r.try_get("id").map_err(|_| AppError::Internal)?,
        sender_id,
        sender_name,
        sender_role: role.map(|role| role_label(&role).to_string()),
        body,
        created_at: created_at.to_rfc3339(),
        pinned: r.try_get("pinned").map_err(|_| AppError::Internal)?,
        pinned_by: r.try_get("pinned_by").map_err(|_| AppError::Internal)?,
        pinned_at: pinned_at.map(|dt| dt.to_rfc3339()),
        reference,
        mentions,
    })
}

/// Réponse de `GET /v1/cabinet/messages/pinned`.
#[derive(Serialize)]
pub struct ListPinnedCabinetTeamMessagesResponse {
    pub data: Vec<CabinetTeamMessageItem>,
}

/// `GET /v1/cabinet/messages/pinned` — messages épinglés du fil (#5130/#8205),
/// quel que soit leur âge.
///
/// Distinct de `GET /v1/cabinet/messages` : ce dernier ne sert qu'une fenêtre
/// des `limit` messages les plus récents (défaut 100, cf. docstring
/// ci-dessus), donc un message épinglé plus ancien que cette fenêtre
/// disparaissait silencieusement du bloc « ÉPINGLÉ » bien qu'`pinned = true`
/// en base (#8205). Cette route n'applique aucune fenêtre/pagination — le
/// nombre de messages épinglés simultanément reste de toute façon faible en
/// pratique.
///
/// Tout membre du staff (`ProSecretaryPlusClaims`) — patient → 403.
/// `cabinet_id` extrait du JWT. Tri chronologique croissant, comme `data`
/// de `GET /v1/cabinet/messages`.
pub async fn list_pinned_cabinet_team_messages(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<ListPinnedCabinetTeamMessagesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT cm.id, cm.sender_id, cm.body, cm.created_at, \
                cm.pinned, cm.pinned_by, cm.pinned_at, \
                cm.reference_type, cm.reference_target_id, \
                cm.reference_title, cm.reference_subtitle, \
                prov.display_name AS provider_display_name, \
                cmb.role AS sender_role \
         FROM cabinet_messages cm \
         LEFT JOIN practitioner p ON p.user_id = cm.sender_id AND p.cabinet_id = cm.cabinet_id \
         LEFT JOIN provider prov ON prov.practitioner_id = p.id AND prov.cabinet_id = cm.cabinet_id \
         LEFT JOIN cabinet_membership cmb ON cmb.user_id = cm.sender_id AND cmb.cabinet_id = cm.cabinet_id \
         WHERE cm.cabinet_id = $1 AND cm.deleted_at IS NULL AND cm.pinned = true \
         ORDER BY cm.created_at ASC, cm.id ASC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let resolved_names = resolve_sender_names(&mut tx, &rows).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(|r| build_message_item(r, &resolved_names))
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(ListPinnedCabinetTeamMessagesResponse { data }))
}

/// Borne haute de `body`, alignée sur `reviews.rs::MAX_COMMENT_LEN` (même
/// ordre de grandeur pour un texte conversationnel libre). Avant #8209,
/// aucune borne n'était posée : un corps de 50 000 caractères était accepté
/// et persisté tel quel.
const MAX_TEAM_MESSAGE_LEN: usize = 4_000;

/// Objet produit joint à l'envoi (#5131/#8208, encadré 3 « Citer un objet
/// du produit » de la maquette) — `type` restreint à
/// [`ALLOWED_REFERENCE_TYPES`].
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SendCabinetTeamMessageReferenceBody {
    #[serde(rename = "type")]
    pub kind: String,
    pub target_id: Uuid,
    pub title: String,
    pub subtitle: String,
}

/// Corps de `POST /v1/cabinet/messages`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SendCabinetTeamMessageBody {
    pub body: String,
    /// Objet produit cité (#8208) — absent tant que le composeur ne permet
    /// pas de joindre un patient/devis (`aria-disabled`, #8195).
    pub reference: Option<SendCabinetTeamMessageReferenceBody>,
}

/// Réponse de `POST /v1/cabinet/messages`.
#[derive(Serialize)]
pub struct SendCabinetTeamMessageResponse {
    pub id: Uuid,
}

/// `POST /v1/cabinet/messages` — envoie un message interne d'équipe (#4156).
///
/// Tout membre du staff (`ProSecretaryPlusClaims`) — patient → 403.
/// `body` vide/blanc, réduit à un ou plusieurs `@` (mention amorcée puis
/// abandonnée, #7738), porteur d'un octet NUL (#4410), ou dépassant
/// [`MAX_TEAM_MESSAGE_LEN`] caractères (#8209) → 422. `reference` optionnel
/// (#8208) — `type` hors [`ALLOWED_REFERENCE_TYPES`] ou `title`/`subtitle`
/// vide/NUL → 422. `cabinet_id`/`sender_id` extraits du JWT.
/// Réponse `201 { id }`.
pub async fn send_cabinet_team_message(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<SendCabinetTeamMessageBody>,
) -> Result<(StatusCode, Json<SendCabinetTeamMessageResponse>), AppError> {
    let text = body.body.trim().to_string();
    // #7738 : le bouton « Mentionner » insère un `@` nu — sans nom derrière,
    // ce n'est le début d'aucune mention (`@[\p{L}\p{N}_]+` en front), donc
    // aucun contenu réel. Traité comme le vide qu'il déguise.
    if text.is_empty() || text.chars().all(|c| c == '@') {
        return Err(AppError::ValidationError);
    }
    // #4410 : NUL byte non filtré → bind Postgres échoue, masqué en 500.
    crate::text_validation::reject_nul_byte(&text)?;
    // #8209 : aucune borne haute sur `body` — un message de 50 000
    // caractères était accepté et persisté tel quel.
    crate::text_validation::validate_max_len(&text, MAX_TEAM_MESSAGE_LEN)?;

    // #8208 : objet produit joint — `type` doit être reconnu, `title`/
    // `subtitle` non vides (mêmes gardes que `body`, pas de NUL).
    if let Some(reference) = &body.reference {
        if !ALLOWED_REFERENCE_TYPES.contains(&reference.kind.as_str())
            || reference.title.trim().is_empty()
            || reference.subtitle.trim().is_empty()
        {
            return Err(AppError::ValidationError);
        }
        crate::text_validation::reject_nul_byte(&reference.title)?;
        crate::text_validation::reject_nul_byte(&reference.subtitle)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO cabinet_messages \
            (cabinet_id, sender_id, body, \
             reference_type, reference_target_id, reference_title, reference_subtitle) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&text)
    .bind(body.reference.as_ref().map(|r| r.kind.clone()))
    .bind(body.reference.as_ref().map(|r| r.target_id))
    .bind(body.reference.as_ref().map(|r| r.title.clone()))
    .bind(body.reference.as_ref().map(|r| r.subtitle.clone()))
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        sender_id = %claims.sub,
        message_id = %id,
        "cabinet team message sent"
    );

    Ok((
        StatusCode::CREATED,
        Json(SendCabinetTeamMessageResponse { id }),
    ))
}

/// Réponse de `POST /v1/cabinet/messages/:id/pin`.
#[derive(Serialize)]
pub struct PinCabinetTeamMessageResponse {
    pub id: Uuid,
    pub pinned: bool,
}

/// `POST /v1/cabinet/messages/:id/pin` — épingle un message du fil (#5130,
/// bloc « ÉPINGLÉ » de l'aside design-v2 ; #8181).
///
/// Tout membre du staff (`ProSecretaryPlusClaims`) — patient → 403. Message
/// hors cabinet, supprimé, ou id inconnu → `404`. Idempotent : épingler un
/// message déjà épinglé ne ré-écrit pas `pinned_by`/`pinned_at`.
pub async fn pin_cabinet_team_message(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(message_id): Path<Uuid>,
) -> Result<Json<PinCabinetTeamMessageResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "UPDATE cabinet_messages \
         SET pinned = true, pinned_by = $3, pinned_at = now() \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL AND pinned = false \
         RETURNING id",
    )
    .bind(message_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if row.is_none() {
        // Déjà épinglé (idempotence) plutôt que 404 : on redistingue des
        // deux cas via une lecture dédiée, sans écraser pinned_by/pinned_at.
        let existing =
            sqlx::query("SELECT id FROM cabinet_messages WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL")
                .bind(message_id)
                .bind(claims.cabinet_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        if existing.is_none() {
            return Err(AppError::NotFound);
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        sender_id = %claims.sub,
        message_id = %message_id,
        "cabinet team message pinned"
    );

    Ok(Json(PinCabinetTeamMessageResponse {
        id: message_id,
        pinned: true,
    }))
}
