//! Détection de doublons du référentiel patient (lot A5, #3916).
//!
//! Quoi : empreinte déterministe de l'INS (`patient.ins_hash`, migration
//! 0262) + flagging des paires de patients d'un même cabinet partageant un
//! INS (`patient_merge_candidate`) + endpoints cabinet de revue humaine.
//! Quand : le flagging est appelé par le chemin ADT (B8, `hl7v2::adt`)
//! après chaque création/màj portant un INS ; la revue par le cabinet via
//! `GET /v1/cabinet/patients/merge-candidates` (+ dismiss).
//! Pourquoi cette approche : l'INS chiffré par enveloppe est non
//! déterministe — indétectable en SQL. Le hash SHA-256 salé par la clé
//! maître KMS (jamais l'INS brut, préimage protégée par le sel serveur)
//! rend l'égalité vérifiable par index sans exposer l'identifiant. AUCUNE
//! fusion automatique (v1) : la résolution humaine passe par le endpoint
//! existant `POST /v1/cabinet/patients/:id/merge` (#4102).
//! Modes d'échec : sans `KMS_MASTER_KEY` le hash n'est pas calculable —
//! le flagging est sauté silencieusement côté ADT (fail-open sur la
//! DÉTECTION seulement, jamais sur les données) ; les endpoints renvoient
//! les erreurs AppError standard.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::Serialize;
use sha2::{Digest, Sha256};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminClaims},
    AppState,
};

/// Empreinte déterministe de l'INS : `sha256(clé_maître_kms || ins)` hex.
/// Salée par la clé serveur pour empêcher toute énumération hors-ligne des
/// 10^15 INS possibles si la colonne fuitait seule.
pub fn ins_hash(ins: &str) -> Option<String> {
    use base64::engine::{general_purpose::STANDARD, Engine};
    let raw = std::env::var("KMS_MASTER_KEY").ok()?;
    let salt = STANDARD.decode(raw.trim()).ok()?;
    let mut hasher = Sha256::new();
    hasher.update(&salt);
    hasher.update(ins.as_bytes());
    Some(hex::encode(hasher.finalize()))
}

/// Flagge les doublons d'INS autour de `patient_id` (qui vient de recevoir
/// `hash`) : toute autre ligne du cabinet avec le même `ins_hash` produit une
/// paire `patient_merge_candidate` (idempotent — UNIQUE sur la paire).
/// `reason` distingue une démographie identique (nom + naissance) d'une
/// démographie divergente (signal fort de collision/erreur de saisie).
pub(crate) async fn flag_ins_duplicates(
    tx: &mut sqlx::Transaction<'static, sqlx::Postgres>,
    cabinet_id: Uuid,
    patient_id: Uuid,
    hash: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO patient_merge_candidate (cabinet_id, patient_a, patient_b, reason) \
         SELECT $1, LEAST(p.id, $2), GREATEST(p.id, $2), \
                CASE WHEN lower(p.last_name) = lower(me.last_name) \
                      AND p.birth_date IS NOT DISTINCT FROM me.birth_date \
                     THEN 'same_ins' ELSE 'same_ins_demographie_divergente' END \
         FROM patient p, patient me \
         WHERE me.id = $2 \
           AND p.cabinet_id = $1 AND p.id <> $2 \
           AND p.ins_hash = $3 AND p.deleted_at IS NULL \
         ON CONFLICT (cabinet_id, patient_a, patient_b) DO NOTHING",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(hash)
    .execute(&mut **tx)
    .await?;
    Ok(())
}

/// Une paire candidate telle que rendue au cabinet.
#[derive(Serialize)]
pub struct MergeCandidateItem {
    pub id: Uuid,
    pub patient_a: Uuid,
    pub patient_a_name: String,
    pub patient_b: Uuid,
    pub patient_b_name: String,
    pub reason: String,
    pub created_at: String,
}

/// `GET /v1/cabinet/patients/merge-candidates` — paires `open` du cabinet,
/// plus récentes d'abord. Rôle `admin` (même niveau que la fusion #4102).
pub(crate) async fn list_merge_candidates(
    State(state): State<AppState>,
    claims: ProAdminClaims,
) -> Result<Json<serde_json::Value>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT c.id, c.patient_a, c.patient_b, c.reason, c.created_at, \
                TRIM(COALESCE(pa.first_name,'') || ' ' || COALESCE(pa.last_name,'')) AS name_a, \
                TRIM(COALESCE(pb.first_name,'') || ' ' || COALESCE(pb.last_name,'')) AS name_b \
         FROM patient_merge_candidate c \
         JOIN patient pa ON pa.id = c.patient_a \
         JOIN patient pb ON pb.id = c.patient_b \
         WHERE c.cabinet_id = $1 AND c.status = 'open' \
         ORDER BY c.created_at DESC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let items = rows
        .into_iter()
        .map(|row| {
            Ok(MergeCandidateItem {
                id: row.try_get("id").map_err(|_| AppError::Internal)?,
                patient_a: row.try_get("patient_a").map_err(|_| AppError::Internal)?,
                patient_a_name: row.try_get("name_a").map_err(|_| AppError::Internal)?,
                patient_b: row.try_get("patient_b").map_err(|_| AppError::Internal)?,
                patient_b_name: row.try_get("name_b").map_err(|_| AppError::Internal)?,
                reason: row.try_get("reason").map_err(|_| AppError::Internal)?,
                created_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                    .map_err(|_| AppError::Internal)?
                    .to_rfc3339(),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(serde_json::json!({ "data": items })))
}

/// `POST /v1/cabinet/patients/merge-candidates/:id/dismiss` — écarte une
/// paire (faux positif, homonymie assumée). Rôle `admin`. Absent → 404.
/// La fusion effective, elle, passe par `POST /v1/cabinet/patients/:id/merge`.
pub(crate) async fn dismiss_merge_candidate(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(candidate_id): Path<Uuid>,
) -> Result<Json<serde_json::Value>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let updated = sqlx::query(
        "UPDATE patient_merge_candidate SET status = 'dismissed' \
         WHERE id = $1 AND cabinet_id = $2 AND status = 'open'",
    )
    .bind(candidate_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(
        serde_json::json!({ "id": candidate_id, "status": "dismissed" }),
    ))
}
