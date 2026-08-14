//! Agrégat tuteurs/dépendants (#4091) — appelé par
//! `patient_detail::get_cabinet_patient` (`PatientAdminSection.guardians`/
//! `.dependents`).
//!
//! Quoi : liens `account_guardianship` (entité plateforme, pas de
//! `cabinet_id`) impliquant le compte plateforme lié au patient cabinet
//! consulté — dans les deux sens (le patient peut être tuteur d'un proche,
//! ou dépendant d'un tuteur).
//!
//! Pourquoi cette approche : `account_guardianship`/`patient_account` ont
//! une RLS scopée au GUC `app.current_account_id` (ni `app.current_cabinet_id`,
//! ni même `app.patient_account_id` utilisé par `patient_coverage` — deux
//! noms de GUC coexistent dans ce schéma pour un concept proche, cf.
//! historique migrations 0023 vs 0025/0045/0062). Lire les DÉPENDANTS du
//! patient consulté ne nécessite qu'une impersonation (policy
//! `account_guardian_read` : un tuteur voit le compte de ses dépendants).
//! Lire les TUTEURS du patient consulté n'a pas d'équivalent (aucune policy
//! ne laisse un dépendant lire le compte de son tuteur) : chaque compte
//! tuteur est donc lu individuellement en impersonifiant son propre
//! `account_id` (policy `account_self_select`), même pattern que
//! `clinical.rs::create_cabinet_patient` pour lire un `patient_account`
//! arbitraire (impersonation `app.current_account_id` le temps d'une
//! lecture ciblée).
//!
//! Modes d'échec : `account_guardianship.active = false` exclu (lien
//! révoqué) ; aucun lien dans un sens ou l'autre → tableau vide (pas
//! `None` — l'issue #4091 demande explicitement `guardians:[]`).

use sqlx::Row;
use uuid::Uuid;

use crate::auth::AppError;

/// `account_guardianship.relationship` décrit le sens dépendant→tuteur
/// (ex. "Jade est l'enfant de Marc"). Pour l'entrée `guardians` (sens
/// tuteur→dépendant), il faut inverser le libellé plutôt que le réutiliser
/// tel quel (#4746 : Marc, le tuteur, s'affichait comme "enfant").
fn invert_relationship(relationship: &str) -> String {
    match relationship {
        "enfant" => "parent",
        "parent" => "enfant",
        other => other,
    }
    .to_string()
}

/// Un lien de tutelle, dans un sens ou dans l'autre.
#[derive(serde::Serialize)]
pub struct GuardianshipLink {
    pub account_id: Uuid,
    pub first_name: String,
    pub last_name: String,
    pub relationship: String,
}

/// Retourne `(guardians, dependents)` du compte `account_id` — tuteurs qui
/// gèrent ce compte, puis comptes que ce compte gère.
pub(crate) async fn aggregate_guardianship(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    account_id: Uuid,
) -> Result<(Vec<GuardianshipLink>, Vec<GuardianshipLink>), AppError> {
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(account_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let links = sqlx::query(
        "SELECT guardian_account_id, dependent_account_id, relationship \
         FROM account_guardianship \
         WHERE (guardian_account_id = $1 OR dependent_account_id = $1) AND active = true",
    )
    .bind(account_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut dependent_ids = Vec::new();
    let mut dependent_relationships = std::collections::HashMap::new();
    let mut guardian_links: Vec<(Uuid, String)> = Vec::new();

    for link in &links {
        let guardian_account_id: Uuid = link
            .try_get("guardian_account_id")
            .map_err(|_| AppError::Internal)?;
        let dependent_account_id: Uuid = link
            .try_get("dependent_account_id")
            .map_err(|_| AppError::Internal)?;
        let relationship: String = link
            .try_get("relationship")
            .map_err(|_| AppError::Internal)?;

        if guardian_account_id == account_id {
            dependent_ids.push(dependent_account_id);
            dependent_relationships.insert(dependent_account_id, relationship);
        } else {
            guardian_links.push((guardian_account_id, invert_relationship(&relationship)));
        }
    }

    // Dépendants : lisibles directement (account_guardian_read, GUC déjà = account_id).
    let mut dependents = Vec::with_capacity(dependent_ids.len());
    if !dependent_ids.is_empty() {
        let rows =
            sqlx::query("SELECT id, first_name, last_name FROM patient_account WHERE id = ANY($1)")
                .bind(&dependent_ids)
                .fetch_all(&mut **tx)
                .await
                .map_err(|_| AppError::Internal)?;

        for row in rows {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
            let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
            let relationship = dependent_relationships.remove(&id).unwrap_or_default();
            dependents.push(GuardianshipLink {
                account_id: id,
                first_name,
                last_name,
                relationship,
            });
        }
    }

    // Tuteurs : un par un, impersonation de chaque compte tuteur (account_self_select).
    let mut guardians = Vec::with_capacity(guardian_links.len());
    for (guardian_account_id, relationship) in guardian_links {
        sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
            .bind(guardian_account_id.to_string())
            .execute(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let row = sqlx::query("SELECT first_name, last_name FROM patient_account WHERE id = $1")
            .bind(guardian_account_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;

        if let Some(row) = row {
            let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
            let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
            guardians.push(GuardianshipLink {
                account_id: guardian_account_id,
                first_name,
                last_name,
                relationship,
            });
        }
    }

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind("")
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

    Ok((guardians, dependents))
}
