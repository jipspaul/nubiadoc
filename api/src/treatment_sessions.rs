//! Découpage automatique d'un plan de traitement en séances + prise de RDV
//! liée (#7173, DP-F16.b — dépend des tables posées par #7174, migration
//! `0288_create_treatment_session.sql`).
//!
//! Trois handlers :
//! - `POST /v1/cabinet/treatment-plans/:id/sessions/propose` — répartit les
//!   actes du plan (non encore affectés à une séance) en `treatment_session`
//!   selon les règles du cabinet (`cabinet_session_rules`). Algorithme pur,
//!   documenté et testé unitairement : [`propose_sessions`] ci-dessous.
//! - `POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/slots` —
//!   propose des créneaux `availability_slot` compatibles (même mécanisme
//!   que `scheduling::create_cabinet_appointment`).
//! - `POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/schedule` —
//!   réserve un créneau proposé et crée le RDV, lié à la séance.
//!
//! Même garde §14 (relation de soin) et même extraction `cabinet_id` depuis
//! le JWT que `treatment_phases.rs`/`treatment_plans.rs`.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::collections::HashMap;
use uuid::Uuid;

use crate::{
    appointments_response::is_exclusion_violation,
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

// ── Algorithme pur de découpage (documenté, sans IA) ─────────────────────────

/// Durée par défaut (minutes) appliquée à un acte sans durée explicite.
/// Aucune colonne de durée par code CCAM n'existe à ce jour (`ccam_act`,
/// migration 0119) : fallback documenté, ajustable par acte via
/// `ProposeSessionsBody::act_overrides` ou globalement via
/// `default_duration_min`.
const DEFAULT_ACT_DURATION_MIN: i32 = 30;

/// Préfixe des codes CCAM de traitement endodontique du catalogue de
/// référence (`HBED001/002/003` — incisive/canine, prémolaire, molaire ;
/// migration 0119). Heuristique documentée : aucune colonne
/// `ccam_act.category` dédiée n'existe encore, remplaçable par
/// `ActOverride::is_endo` acte par acte.
const ENDO_CCAM_PREFIX: &str = "HBED";

fn is_endo_ccam_code(code: Option<&str>) -> bool {
    code.map(|c| c.starts_with(ENDO_CCAM_PREFIX))
        .unwrap_or(false)
}

/// Quadrant FDI (1er chiffre du code dent à 2 chiffres), si le code est
/// valide — même validation que `treatment_phases::is_valid_fdi_tooth`,
/// dupliquée ici faute de module de validation partagé pour une fonction
/// aussi courte.
fn fdi_quadrant(tooth: &str) -> Option<u8> {
    if tooth.len() != 2 || !tooth.chars().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let quadrant = tooth.as_bytes()[0] - b'0';
    let n = tooth.as_bytes()[1] - b'0';
    let valid = match quadrant {
        1..=4 => (1..=8).contains(&n),
        5..=8 => (1..=5).contains(&n),
        _ => false,
    };
    if valid {
        Some(quadrant)
    } else {
        None
    }
}

/// Arcade dentaire — quadrants FDI 1/2 (permanente) et 5/6 (temporaire) sont
/// maxillaires (arcade haute) ; 3/4 et 7/8 mandibulaires (arcade basse).
#[derive(Clone, Copy, PartialEq, Eq)]
enum Arch {
    Maxillary,
    Mandibular,
    Unknown,
}

fn arch_of(tooth: Option<&str>) -> Arch {
    match tooth.and_then(fdi_quadrant) {
        Some(1) | Some(2) | Some(5) | Some(6) => Arch::Maxillary,
        Some(3) | Some(4) | Some(7) | Some(8) => Arch::Mandibular,
        _ => Arch::Unknown,
    }
}

/// Secteur = quadrant FDI brut (1..8) ; `0` sentinelle si le code dent est
/// absent ou invalide (les actes sans dent renseignée forment leur propre
/// secteur, plutôt que de rejoindre arbitrairement le secteur 1).
fn sector_of(tooth: Option<&str>) -> u8 {
    tooth.and_then(fdi_quadrant).unwrap_or(0)
}

/// Un acte du plan à répartir en séances — durée et indicateur endo déjà
/// résolus par l'appelant (colonnes DB + overrides), le code dent brut pour
/// que l'algorithme dérive lui-même arcade/secteur.
#[derive(Debug, Clone)]
pub struct PlanActInput {
    pub quote_item_id: Uuid,
    pub duration_min: i32,
    pub tooth: Option<String>,
    pub is_endo: bool,
}

/// Règles de découpage du cabinet (`cabinet_session_rules`, migration 0288).
/// `Default` reproduit les valeurs par défaut de la table (absence de ligne
/// cabinet = ces valeurs, cf. commentaire de la migration).
#[derive(Debug, Clone)]
pub struct SessionRules {
    pub max_duration_min: Option<i32>,
    pub separate_arches: bool,
    pub group_by_sector: bool,
    pub multi_endo: bool,
}

impl Default for SessionRules {
    fn default() -> Self {
        Self {
            max_duration_min: None,
            separate_arches: false,
            group_by_sector: false,
            multi_endo: true,
        }
    }
}

/// Une séance proposée par l'algorithme : durée cumulée + actes qui la
/// composent, dans l'ordre où ils ont été affectés.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProposedSession {
    pub duration_min: i32,
    pub quote_item_ids: Vec<Uuid>,
}

type BucketKey = (Option<Arch>, Option<u8>);

fn bucket_key(act: &PlanActInput, rules: &SessionRules) -> BucketKey {
    let arch = rules.separate_arches.then(|| arch_of(act.tooth.as_deref()));
    let sector = rules
        .group_by_sector
        .then(|| sector_of(act.tooth.as_deref()));
    (arch, sector)
}

/// Découpe `acts` (dans l'ordre reçu — l'ordre du plan, cf. `ORDER BY
/// tph.position, qi.id` de l'appelant) en séances, selon `rules`.
///
/// Algorithme en deux passes, déterministe :
/// 1. **Regroupement** : chaque acte est rangé dans un « bucket » identifié
///    par `(arcade si separate_arches, secteur si group_by_sector)` — les
///    deux critères sont indépendants et se combinent (ex: `separate_arches
///    && group_by_sector` isole chaque secteur de chaque arcade). Un bucket
///    apparaît dans l'ordre du premier acte qui y tombe (stable, pas de tri).
/// 2. **Remplissage glouton par bucket** : les actes d'un bucket sont ajoutés
///    un par un à la séance courante tant que :
///    - `max_duration_min` (si fixé) n'est pas dépassé — un acte qui dépasse
///      `max_duration_min` à lui seul reste néanmoins accepté, seul dans sa
///      propre séance (aucune découpe d'acte : ce n'est pas la responsabilité
///      de cet algorithme) ;
///    - `multi_endo` l'autorise — si `false`, un acte endo ne peut pas
///      rejoindre une séance qui contient déjà un autre acte endo (mais peut
///      partager une séance avec des actes non-endo).
///
///    Dès qu'une contrainte est violée, la séance courante est close et une
///    nouvelle séance démarre avec l'acte qui ne rentrait pas.
///
/// Séances numérotées par la position dans la liste retournée — l'appelant
/// (handler HTTP) assigne `treatment_session.position` en conséquence.
pub fn propose_sessions(acts: &[PlanActInput], rules: &SessionRules) -> Vec<ProposedSession> {
    let mut buckets: Vec<(BucketKey, Vec<&PlanActInput>)> = Vec::new();
    for act in acts {
        let key = bucket_key(act, rules);
        match buckets.iter_mut().find(|(k, _)| *k == key) {
            Some((_, bucket)) => bucket.push(act),
            None => buckets.push((key, vec![act])),
        }
    }

    let mut sessions = Vec::new();
    for (_, bucket_acts) in buckets {
        let mut current: Option<ProposedSession> = None;
        let mut current_has_endo = false;

        for act in bucket_acts {
            let fits_duration = match (&current, rules.max_duration_min) {
                (Some(session), Some(max)) => session.duration_min + act.duration_min <= max,
                _ => true,
            };
            let fits_endo = !(act.is_endo && current_has_endo && !rules.multi_endo);
            let can_extend = fits_duration && fits_endo;

            match current.as_mut() {
                Some(session) if can_extend => {
                    session.duration_min += act.duration_min;
                    session.quote_item_ids.push(act.quote_item_id);
                }
                _ => {
                    if let Some(session) = current.take() {
                        sessions.push(session);
                    }
                    current = Some(ProposedSession {
                        duration_min: act.duration_min,
                        quote_item_ids: vec![act.quote_item_id],
                    });
                    current_has_endo = false;
                }
            }
            if act.is_endo {
                current_has_endo = true;
            }
        }
        if let Some(session) = current {
            sessions.push(session);
        }
    }
    sessions
}

#[cfg(test)]
mod propose_sessions_tests {
    use super::*;

    fn act(duration_min: i32, tooth: Option<&str>, is_endo: bool) -> PlanActInput {
        PlanActInput {
            quote_item_id: Uuid::new_v4(),
            duration_min,
            tooth: tooth.map(str::to_string),
            is_endo,
        }
    }

    // Scénario 1 : aucune règle active (défauts) → tous les actes tiennent
    // dans une seule séance, quelle que soit l'arcade/le secteur.
    #[test]
    fn no_rules_packs_everything_in_one_session() {
        let acts = vec![
            act(30, Some("11"), false),
            act(20, Some("46"), false),
            act(15, None, false),
        ];
        let sessions = propose_sessions(&acts, &SessionRules::default());

        assert_eq!(sessions.len(), 1);
        assert_eq!(sessions[0].duration_min, 65);
        assert_eq!(sessions[0].quote_item_ids.len(), 3);
    }

    // Scénario 2 : max_duration_min dépassé → nouvelle séance, sans jamais
    // dépasser la limite au sein d'une même séance.
    #[test]
    fn max_duration_splits_sessions() {
        let acts = vec![
            act(30, None, false),
            act(30, None, false),
            act(30, None, false),
        ];
        let rules = SessionRules {
            max_duration_min: Some(60),
            ..SessionRules::default()
        };
        let sessions = propose_sessions(&acts, &rules);

        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].duration_min, 60);
        assert_eq!(sessions[0].quote_item_ids.len(), 2);
        assert_eq!(sessions[1].duration_min, 30);
        assert_eq!(sessions[1].quote_item_ids.len(), 1);
    }

    // Scénario 3 : separate_arches → maxillaire et mandibulaire jamais dans
    // la même séance, même entrelacés en entrée.
    #[test]
    fn separate_arches_never_mixes_upper_and_lower() {
        let acts = vec![
            act(20, Some("11"), false), // maxillaire
            act(20, Some("31"), false), // mandibulaire
            act(20, Some("21"), false), // maxillaire
            act(20, Some("41"), false), // mandibulaire
        ];
        let rules = SessionRules {
            separate_arches: true,
            ..SessionRules::default()
        };
        let sessions = propose_sessions(&acts, &rules);

        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].duration_min, 40);
        assert_eq!(sessions[1].duration_min, 40);
        // Chaque séance ne mélange jamais les deux arcades (vérifié via les
        // deux actes maxillaires groupés dans la 1ère séance rencontrée).
        let maxillary_ids: Vec<Uuid> = acts
            .iter()
            .filter(|a| arch_of(a.tooth.as_deref()) == Arch::Maxillary)
            .map(|a| a.quote_item_id)
            .collect();
        assert_eq!(sessions[0].quote_item_ids, maxillary_ids);
    }

    // Scénario 4 : group_by_sector → un secteur (quadrant FDI) par séance.
    #[test]
    fn group_by_sector_splits_by_quadrant() {
        let acts = vec![
            act(20, Some("11"), false), // secteur 1
            act(20, Some("31"), false), // secteur 3
            act(20, Some("12"), false), // secteur 1
        ];
        let rules = SessionRules {
            group_by_sector: true,
            ..SessionRules::default()
        };
        let sessions = propose_sessions(&acts, &rules);

        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].quote_item_ids.len(), 2); // secteur 1
        assert_eq!(sessions[1].quote_item_ids.len(), 1); // secteur 3
    }

    // Scénario 5 : multi_endo = false → deux actes endo ne peuvent jamais
    // partager une séance (un acte non-endo peut s'intercaler librement).
    #[test]
    fn multi_endo_false_isolates_each_endo_act() {
        let acts = vec![
            act(30, Some("11"), true),  // endo #1
            act(20, Some("12"), false), // non-endo, peut rejoindre endo #1
            act(30, Some("13"), true),  // endo #2 : ne peut pas rejoindre endo #1
        ];
        let rules = SessionRules {
            multi_endo: false,
            ..SessionRules::default()
        };
        let sessions = propose_sessions(&acts, &rules);

        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].duration_min, 50);
        assert_eq!(sessions[0].quote_item_ids.len(), 2);
        assert_eq!(sessions[1].duration_min, 30);
        assert_eq!(sessions[1].quote_item_ids.len(), 1);
    }

    // Scénario complémentaire : un acte seul dépasse déjà max_duration_min —
    // accepté seul dans sa propre séance plutôt que rejeté/découpé.
    #[test]
    fn single_act_longer_than_max_gets_its_own_session() {
        let acts = vec![act(90, None, false), act(10, None, false)];
        let rules = SessionRules {
            max_duration_min: Some(60),
            ..SessionRules::default()
        };
        let sessions = propose_sessions(&acts, &rules);

        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].duration_min, 90);
        assert_eq!(sessions[1].duration_min, 10);
    }
}

// ── Handlers HTTP ─────────────────────────────────────────────────────────────

/// Vérifie que le praticien appelant a eu au moins un `appointment` avec le
/// patient dans ce cabinet (403 sinon) — même garde §14 que
/// `treatment_phases.rs::ensure_care_relationship`, dupliquée ici faute de
/// module partagé (cf. commentaire équivalent dans ce fichier).
async fn ensure_care_relationship(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_id: Uuid,
    cabinet_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(user_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }
    Ok(())
}

async fn fetch_session_rules(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
) -> Result<SessionRules, AppError> {
    let row = sqlx::query(
        "SELECT max_duration_min, separate_arches, group_by_sector, multi_endo \
         FROM cabinet_session_rules WHERE cabinet_id = $1",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        return Ok(SessionRules::default());
    };
    Ok(SessionRules {
        max_duration_min: row
            .try_get("max_duration_min")
            .map_err(|_| AppError::Internal)?,
        separate_arches: row
            .try_get("separate_arches")
            .map_err(|_| AppError::Internal)?,
        group_by_sector: row
            .try_get("group_by_sector")
            .map_err(|_| AppError::Internal)?,
        multi_endo: row.try_get("multi_endo").map_err(|_| AppError::Internal)?,
    })
}

// ── POST /v1/cabinet/treatment-plans/:id/sessions/propose ────────────────────

/// Override ponctuel par acte (`quote_item_id`) — permet au praticien
/// d'ajuster durée/indicateur endo sans dépendre d'un référentiel
/// CCAM → durée pas encore modélisé (cf. `DEFAULT_ACT_DURATION_MIN`).
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActOverride {
    pub quote_item_id: Uuid,
    pub duration_min: Option<i32>,
    pub is_endo: Option<bool>,
}

/// Corps de `POST /v1/cabinet/treatment-plans/:id/sessions/propose`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProposeSessionsBody {
    #[serde(default = "default_act_duration_min")]
    pub default_duration_min: i32,
    #[serde(default)]
    pub act_overrides: Vec<ActOverride>,
}

fn default_act_duration_min() -> i32 {
    DEFAULT_ACT_DURATION_MIN
}

#[derive(Serialize)]
pub struct ProposedSessionItem {
    pub session_id: Uuid,
    pub position: i32,
    pub duration_min: i32,
    pub quote_item_ids: Vec<Uuid>,
}

#[derive(Serialize)]
pub struct ProposeSessionsResponse {
    pub sessions: Vec<ProposedSessionItem>,
}

/// `POST /v1/cabinet/treatment-plans/:id/sessions/propose` — répartit les
/// actes du plan pas encore affectés à une séance, selon
/// `cabinet_session_rules` (défauts si absente).
///
/// Praticien uniquement (via `ProPractitionerClaims`). Plan inexistant, hors
/// tenant, ou `done` (terminal) → 404/422. Aucun acte à répartir (tous les
/// `quote_item` du plan sont déjà affectés à une séance, ou le plan n'en a
/// aucun) → 422. Persiste directement les `treatment_session` +
/// `treatment_session_act` proposées (statut initial `planned`), à la suite
/// des séances déjà existantes du plan (`position` = max existant + 1..N).
pub async fn propose_treatment_sessions(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(plan_id): Path<Uuid>,
    Json(body): Json<ProposeSessionsBody>,
) -> Result<(StatusCode, Json<ProposeSessionsResponse>), AppError> {
    if body.default_duration_min <= 0 {
        return Err(AppError::ValidationError);
    }
    for over in &body.act_overrides {
        if matches!(over.duration_min, Some(d) if d <= 0) {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let plan_row = sqlx::query(
        "SELECT patient_id, status FROM treatment_plan \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let Some(plan_row) = plan_row else {
        return Err(AppError::NotFound);
    };
    let patient_id: Uuid = plan_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let plan_status: String = plan_row.try_get("status").map_err(|_| AppError::Internal)?;

    ensure_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub).await?;

    if plan_status == "done" {
        return Err(AppError::ValidationError);
    }

    // Actes du plan (via les phases, cf. treatment_phases.rs) pas encore
    // affectés à une séance existante — un `propose` répété ne redécoupe
    // jamais un acte déjà planifié.
    let act_rows = sqlx::query(
        "SELECT qi.id, qi.tooth, qi.ccam_code \
         FROM quote_item qi \
         JOIN treatment_phase tph ON tph.id = qi.phase_id \
         WHERE tph.plan_id = $1 AND qi.cabinet_id = $2 \
           AND NOT EXISTS ( \
               SELECT 1 FROM treatment_session_act tsa \
               WHERE tsa.quote_item_id = qi.id AND tsa.cabinet_id = $2 \
           ) \
         ORDER BY tph.position, qi.id",
    )
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if act_rows.is_empty() {
        return Err(AppError::ValidationError);
    }

    let overrides: HashMap<Uuid, &ActOverride> = body
        .act_overrides
        .iter()
        .map(|o| (o.quote_item_id, o))
        .collect();

    let mut acts = Vec::with_capacity(act_rows.len());
    for row in &act_rows {
        let quote_item_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
        let ccam_code: Option<String> = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
        let over = overrides.get(&quote_item_id);
        let duration_min = over
            .and_then(|o| o.duration_min)
            .unwrap_or(body.default_duration_min);
        let is_endo = over
            .and_then(|o| o.is_endo)
            .unwrap_or_else(|| is_endo_ccam_code(ccam_code.as_deref()));
        acts.push(PlanActInput {
            quote_item_id,
            duration_min,
            tooth,
            is_endo,
        });
    }

    let rules = fetch_session_rules(&mut tx, claims.cabinet_id).await?;
    let proposed = propose_sessions(&acts, &rules);

    let base_position: i32 = sqlx::query(
        "SELECT coalesce(max(position), 0) AS max_position FROM treatment_session \
         WHERE plan_id = $1 AND cabinet_id = $2",
    )
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .try_get("max_position")
    .map_err(|_| AppError::Internal)?;

    let mut created = Vec::with_capacity(proposed.len());
    for (offset, session) in proposed.into_iter().enumerate() {
        let position = base_position + 1 + offset as i32;

        let session_id: Uuid = sqlx::query(
            "INSERT INTO treatment_session (cabinet_id, plan_id, position, duration_min, status) \
             VALUES ($1, $2, $3, $4, 'planned') RETURNING id",
        )
        .bind(claims.cabinet_id)
        .bind(plan_id)
        .bind(position)
        .bind(session.duration_min)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get("id")
        .map_err(|_| AppError::Internal)?;

        for quote_item_id in &session.quote_item_ids {
            sqlx::query(
                "INSERT INTO treatment_session_act (cabinet_id, session_id, quote_item_id) \
                 VALUES ($1, $2, $3)",
            )
            .bind(claims.cabinet_id)
            .bind(session_id)
            .bind(quote_item_id)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        }

        created.push(ProposedSessionItem {
            session_id,
            position,
            duration_min: session.duration_min,
            quote_item_ids: session.quote_item_ids,
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        plan_id = %plan_id,
        sessions_created = created.len(),
        "treatment sessions proposed"
    );

    Ok((
        StatusCode::CREATED,
        Json(ProposeSessionsResponse { sessions: created }),
    ))
}

// ── POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/slots ───────────

/// Corps de `POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/slots`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProposeSlotsBody {
    /// Praticien à interroger — sinon `treatment_plan.practitioner_id`
    /// (422 si aucun des deux n'est renseigné).
    pub practitioner_id: Option<Uuid>,
    pub from: Option<String>,
    pub to: Option<String>,
}

#[derive(Serialize)]
pub struct ProposedSlotItem {
    pub slot_id: Uuid,
    pub practitioner_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
}

#[derive(Serialize)]
pub struct ProposeSlotsResponse {
    pub slots: Vec<ProposedSlotItem>,
}

/// `POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/slots` — liste
/// jusqu'à 20 créneaux `availability_slot` ouverts, assez longs pour la
/// durée de la séance, du praticien résolu (`body.practitioner_id` ou
/// `treatment_plan.practitioner_id`), triés par date croissante. Même
/// filtre `provider_unavailability` que `scheduling::create_cabinet_slot`.
/// Plan/séance inexistants ou hors tenant → 404. Aucun praticien résolu
/// → 422.
pub async fn propose_session_slots(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path((plan_id, session_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<ProposeSlotsBody>,
) -> Result<Json<ProposeSlotsResponse>, AppError> {
    let from = body
        .from
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let to = body
        .to
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let plan_row = sqlx::query(
        "SELECT patient_id, practitioner_id FROM treatment_plan \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let patient_id: Uuid = plan_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let plan_practitioner_id: Option<Uuid> = plan_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    ensure_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub).await?;

    let session_row = sqlx::query(
        "SELECT duration_min FROM treatment_session \
         WHERE id = $1 AND plan_id = $2 AND cabinet_id = $3",
    )
    .bind(session_id)
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let duration_min: i32 = session_row
        .try_get("duration_min")
        .map_err(|_| AppError::Internal)?;

    let practitioner_id = body
        .practitioner_id
        .or(plan_practitioner_id)
        .ok_or(AppError::ValidationError)?;

    let practitioner_exists =
        sqlx::query("SELECT 1 FROM practitioner WHERE id = $1 AND cabinet_id = $2")
            .bind(practitioner_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if practitioner_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let rows = sqlx::query(
        "SELECT sl.id, sl.starts_at, sl.ends_at FROM availability_slot sl \
         WHERE sl.cabinet_id = $1 AND sl.practitioner_id = $2 AND sl.status = 'open' \
           AND sl.deleted_at IS NULL AND sl.starts_at > now() \
           AND (extract(epoch FROM (sl.ends_at - sl.starts_at)) / 60)::float8 >= $3 \
           AND ($4::timestamptz IS NULL OR sl.starts_at >= $4) \
           AND ($5::timestamptz IS NULL OR sl.starts_at < $5) \
           AND NOT EXISTS ( \
               SELECT 1 FROM provider_unavailability pu \
               JOIN provider prov ON prov.id = pu.provider_id \
               WHERE prov.practitioner_id = sl.practitioner_id \
                 AND pu.starts_at < sl.ends_at AND pu.ends_at > sl.starts_at \
           ) \
         ORDER BY sl.starts_at ASC LIMIT 20",
    )
    .bind(claims.cabinet_id)
    .bind(practitioner_id)
    .bind(duration_min)
    .bind(from)
    .bind(to)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut slots = Vec::with_capacity(rows.len());
    for row in rows {
        let slot_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        let ends_at: chrono::DateTime<chrono::Utc> =
            row.try_get("ends_at").map_err(|_| AppError::Internal)?;
        slots.push(ProposedSlotItem {
            slot_id,
            practitioner_id,
            starts_at: starts_at.to_rfc3339(),
            ends_at: ends_at.to_rfc3339(),
        });
    }

    Ok(Json(ProposeSlotsResponse { slots }))
}

// ── POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/schedule ────────

/// Corps de `POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/schedule`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ScheduleSessionBody {
    pub slot_id: Uuid,
    pub notes: Option<String>,
}

#[derive(Serialize)]
pub struct ScheduleSessionResponse {
    pub appointment_id: Uuid,
    pub session_id: Uuid,
    pub status: String,
}

/// `POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/schedule` —
/// réserve `slot_id` (`availability_slot` ouvert du cabinet) et crée le RDV
/// (statut initial `requested`, même convention que
/// `scheduling::create_cabinet_appointment`), lié à la séance
/// (`treatment_session.appointment_id`, statut → `scheduled`).
///
/// Plan/séance inexistants ou hors tenant → 404. Séance déjà `scheduled` (ou
/// plus avancée) → 409 `session_already_scheduled`. Créneau inexistant, hors
/// tenant, ou supprimé → 404 ; non `open` ou couvert par une indisponibilité
/// praticien → 409 `slot_taken`. Créneau plus court que la durée de la
/// séance → 422 (jamais de RDV plus court que les actes qu'il doit porter).
pub async fn schedule_treatment_session(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path((plan_id, session_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<ScheduleSessionBody>,
) -> Result<(StatusCode, Json<ScheduleSessionResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let plan_row = sqlx::query(
        "SELECT patient_id FROM treatment_plan \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let patient_id: Uuid = plan_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    ensure_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub).await?;

    let session_row = sqlx::query(
        "SELECT status, duration_min FROM treatment_session \
         WHERE id = $1 AND plan_id = $2 AND cabinet_id = $3",
    )
    .bind(session_id)
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let session_status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let duration_min: i32 = session_row
        .try_get("duration_min")
        .map_err(|_| AppError::Internal)?;

    if session_status != "planned" {
        return Err(AppError::SessionAlreadyScheduled);
    }

    let slot_row = sqlx::query(
        "SELECT starts_at, ends_at, practitioner_id, \
                (extract(epoch FROM (ends_at - starts_at)) / 60)::float8 AS slot_duration_min \
         FROM availability_slot \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL AND status = 'open' \
           AND NOT EXISTS ( \
               SELECT 1 FROM provider_unavailability pu \
               JOIN provider prov ON prov.id = pu.provider_id \
               WHERE prov.practitioner_id = availability_slot.practitioner_id \
                 AND pu.starts_at < availability_slot.ends_at \
                 AND pu.ends_at > availability_slot.starts_at \
           )",
    )
    .bind(body.slot_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::SlotTaken)?;

    let starts_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("starts_at")
        .map_err(|_| AppError::Internal)?;
    let ends_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("ends_at")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = slot_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let slot_duration_min: f64 = slot_row
        .try_get("slot_duration_min")
        .map_err(|_| AppError::Internal)?;

    if slot_duration_min < f64::from(duration_min) {
        return Err(AppError::ValidationError);
    }

    // INSERT — 23P01 (appointment_no_overlap) → 409 slot_taken.
    let result = sqlx::query(
        "INSERT INTO appointment \
         (cabinet_id, patient_id, practitioner_id, slot_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, $5, $6, 'requested', $7) \
         RETURNING id, status",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(body.slot_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(body.notes.as_deref())
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(r) => r,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };
    let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE availability_slot SET status = 'booked', updated_at = now() \
         WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(body.slot_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE treatment_session \
         SET appointment_id = $1, status = 'scheduled', updated_at = now() \
         WHERE id = $2 AND cabinet_id = $3",
    )
    .bind(appointment_id)
    .bind(session_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'create_appointment', 'appointment', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(appointment_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        plan_id = %plan_id,
        session_id = %session_id,
        appointment_id = %appointment_id,
        "treatment session scheduled"
    );

    Ok((
        StatusCode::CREATED,
        Json(ScheduleSessionResponse {
            appointment_id,
            session_id,
            status,
        }),
    ))
}
