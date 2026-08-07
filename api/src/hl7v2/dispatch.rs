//! Dispatch HL7 v2 (lot B7) : résout le partenaire (empreinte de certificat
//! client mTLS, B5) puis le cabinet cible (`MSH-4`/`MSH-6`, B6), vérifie
//! l'idempotence (`MSH-10`), journalise dans `audit_log`, et construit l'ACK
//! à renvoyer sur la connexion MLLP.
//!
//! ## Interface cross-lots (B5/B6 pas présents dans ce worktree)
//!
//! - **B5** (`agent/interop-hl7v2-tls`) : extrait l'empreinte SHA-256 du
//!   certificat client. Ce module ne fait que *recevoir* cette empreinte déjà
//!   extraite (`fingerprint: &str`) — pas d'appel à `hl7v2::tls` ici.
//! - **B6** (`agent/interop-hl7v2-partner-migration`) : migration créant
//!   `hl7v2_partner`, `hl7v2_partner_facility_map` (RLS tenant-scopée),
//!   `hl7v2_message_log`, plus des fonctions `SECURITY DEFINER`.
//!
//! Ces tables/fonctions n'existent pas ici : on utilise `sqlx::query`/
//! `query_scalar` (runtime, pas la macro `query!` compile-time) pour rester
//! compilable de façon autonome. Voir les commentaires `ASSOMPTION` pour le
//! détail des formes supposées, à revalider à l'intégration des 3 branches.
//!
//! Consommé par `api/src/hl7v2/listener.rs` (lot B10), qui appelle
//! [`dispatch`] pour chaque message MLLP reçu.
//!
//! Le traitement métier (`process_message`) branche `ADT` sur
//! [`crate::interop::patient`] (lot B8, mapping ADT vers la couche service
//! patient) et `SIU` sur [`crate::hl7v2::siu`] (lot B9, agenda).

use core_crypto::KeyManager;
use core_tenancy::with_tenant;
use integrations_hl7v2::{
    ack::{build_ack, AckCode, AckParams},
    message::Message,
};
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::hl7v2::siu;
use crate::interop::patient as adt_patient;

/// Pourquoi un message a été rejeté (ACK `AR`/`AE`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RejectReason {
    /// Absent de `hl7v2_partner`, ou `status != 'active'`.
    UnknownOrInactivePartner,
    /// Partenaire actif, mais aucun mapping `(partner_id, MSH-4, MSH-6)`.
    UnknownFacilityMapping,
    /// Échec technique (DB, etc.) — pas une décision métier ; l'appelant
    /// (métriques/alerting) doit pouvoir distinguer ce cas des deux autres.
    Internal,
    /// Partenaire/cabinet résolus, message frais, mais le contenu métier
    /// (ADT/SIU) n'a pas pu être traité (lot B9, ex. patient/practitioner
    /// inconnu, créneau occupé, type de message non supporté). Contrairement
    /// aux autres variantes, la décision de dédup (MSH-10) a déjà eu lieu
    /// **avant** cet échec — un rejeu du même message par l'émetteur sera vu
    /// comme un doublon (`AA`), pas retraité. Limitation connue héritée du
    /// lot B7 (dédup avant traitement métier), pas introduite par B9.
    ProcessingFailed(String),
}

/// Issue du dispatch pour un message donné.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DispatchStatus {
    /// Frais : partenaire actif, cabinet résolu, pas de doublon — traité par
    /// `process_message` (ADT stub B8 / SIU réel B9) et audité.
    Accepted { partner_id: Uuid, cabinet_id: Uuid },
    /// `MSH-10` déjà vu pour ce partenaire : effet déjà produit, on ne
    /// re-traite pas (pas de second `audit_log`), mais l'ACK reste `AA`
    /// (l'émetteur ne doit pas re-livrer).
    Duplicate { partner_id: Uuid, cabinet_id: Uuid },
    /// Rejeté avant tout traitement — voir [`RejectReason`].
    Rejected(RejectReason),
}

/// Résultat complet d'un [`dispatch`] : l'ACK à renvoyer tel quel sur MLLP,
/// plus le statut pour le logging/les métriques appelant.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DispatchOutcome {
    pub status: DispatchStatus,
    /// Octets ACK (`MSH`+`MSA`, terminés par `\r`), via [`build_ack`].
    pub ack: String,
}

/// Résout le partenaire et le cabinet cible à partir de l'empreinte de
/// certificat et du message HL7 v2 déjà parsé, puis journalise et renvoie
/// l'ACK approprié.
///
/// Ne panique jamais : toute erreur technique est convertie en
/// [`RejectReason::Internal`] (ACK `AE`) — l'appelant MLLP doit toujours
/// pouvoir écrire quelque chose sur le socket.
pub async fn dispatch(
    pool: &PgPool,
    fingerprint: &str,
    message: &Message,
    key_manager: &dyn KeyManager,
) -> DispatchOutcome {
    let control_id = msh_field(message, 10).unwrap_or_default();
    let message_type = msh_field(message, 9).unwrap_or_default();

    // ── 1. Partenaire (empreinte mTLS, B5) ──────────────────────────────
    let partner = match find_partner_by_fingerprint(pool, fingerprint).await {
        Ok(Some(p)) if p.status == "active" => p,
        Ok(_) => return reject(&control_id, RejectReason::UnknownOrInactivePartner),
        Err(err) => {
            tracing::warn!(error = %err, "hl7v2 dispatch: échec résolution partenaire");
            return reject(&control_id, RejectReason::Internal);
        }
    };

    // ── 2. MSH-4 (émetteur) / MSH-6 (destinataire) ──────────────────────
    let sending_facility = msh_field(message, 4).unwrap_or_default();
    let receiving_facility = msh_field(message, 6).unwrap_or_default();

    // ── 3. Cabinet cible ─────────────────────────────────────────────────
    let cabinet_id =
        match find_cabinet_for_facility(pool, partner.id, &sending_facility, &receiving_facility)
            .await
        {
            Ok(Some(id)) => id,
            Ok(None) => return reject(&control_id, RejectReason::UnknownFacilityMapping),
            Err(err) => {
                tracing::warn!(error = %err, "hl7v2 dispatch: échec résolution cabinet");
                return reject(&control_id, RejectReason::Internal);
            }
        };

    // ── 4 + 5. Idempotence (MSH-10) + audit, tenant = cabinet résolu ────
    match check_idempotency_and_audit(pool, cabinet_id, partner.id, &control_id, &message_type)
        .await
    {
        Ok(true) => {
            // ── 6. Traitement métier (ADT stub B8 / SIU réel B9) ────────
            match process_message(
                pool,
                cabinet_id,
                partner.id,
                message,
                &message_type,
                key_manager,
            )
            .await
            {
                Ok(()) => accept(
                    &control_id,
                    DispatchStatus::Accepted {
                        partner_id: partner.id,
                        cabinet_id,
                    },
                ),
                Err(detail) => reject(&control_id, RejectReason::ProcessingFailed(detail)),
            }
        }
        Ok(false) => accept(
            &control_id,
            DispatchStatus::Duplicate {
                partner_id: partner.id,
                cabinet_id,
            },
        ),
        Err(err) => {
            tracing::warn!(error = %err, "hl7v2 dispatch: échec idempotence/audit");
            reject(&control_id, RejectReason::Internal)
        }
    }
}

/// Ligne minimale de `hl7v2_partner` utile au dispatch.
struct PartnerRow {
    id: Uuid,
    status: String,
}

/// Résout le partenaire à partir de l'empreinte SHA-256 du certificat client.
///
/// ASSOMPTION (B6) : `hl7v2_partner_find_by_fingerprint(p_fingerprint text)`
/// est `SECURITY DEFINER` (comme `payment_find_by_provider_ref`, cf.
/// `webhooks/stripe.rs`), renvoie la ligne `hl7v2_partner` (au moins
/// `id uuid`, `status text`) ou zéro ligne. `hl7v2_partner` = registre
/// plateforme (pas de RLS tenant) → appel sur le pool nu, sans `with_tenant`.
async fn find_partner_by_fingerprint(
    pool: &PgPool,
    fingerprint: &str,
) -> Result<Option<PartnerRow>, sqlx::Error> {
    let row = sqlx::query("SELECT id, status FROM hl7v2_partner_find_by_fingerprint($1)")
        .bind(fingerprint)
        .fetch_optional(pool)
        .await?;
    match row {
        Some(r) => Ok(Some(PartnerRow {
            id: r.try_get("id")?,
            status: r.try_get("status")?,
        })),
        None => Ok(None),
    }
}

/// Résout le `cabinet_id` cible à partir de `(partner_id, MSH-4, MSH-6)`.
///
/// ASSOMPTION (B6, non détaillée dans le brief B7) : `hl7v2_partner_facility_map`
/// porte une RLS tenant-scopée sur `cabinet_id`, donc — comme pour
/// `payment_find_by_provider_ref` côté Stripe — la résolution initiale (avant
/// tout `cabinet_id` connu) doit passer par une fonction `SECURITY DEFINER`.
/// Nom retenu ici par simplicité/convention avec `hl7v2_partner_find_by_fingerprint` :
/// `hl7v2_partner_facility_map_find_cabinet(p_partner_id uuid, p_sending_facility
/// text, p_receiving_facility text) returns uuid` — à confirmer avec B6 au merge.
async fn find_cabinet_for_facility(
    pool: &PgPool,
    partner_id: Uuid,
    sending_facility: &str,
    receiving_facility: &str,
) -> Result<Option<Uuid>, sqlx::Error> {
    let row =
        sqlx::query("SELECT cabinet_id FROM hl7v2_partner_facility_map_find_cabinet($1, $2, $3)")
            .bind(partner_id)
            .bind(sending_facility)
            .bind(receiving_facility)
            .fetch_optional(pool)
            .await?;
    match row {
        Some(r) => Ok(Some(r.try_get("cabinet_id")?)),
        None => Ok(None),
    }
}

/// Vérifie l'idempotence (`MSH-10`) puis, si le message est frais, écrit
/// `audit_log` — dans une seule transaction tenant-scopée (`with_tenant`)
/// pour rester atomique. `true` = frais (à traiter), `false` = doublon vu.
///
/// ASSOMPTION (B6) : `hl7v2_message_log_check_and_insert(p_partner_id uuid,
/// p_control_id text) returns boolean` est la fonction atomique de
/// dédoublonnage du brief. `hl7v2_message_log` supposé tenant-scopé (comme
/// `audit_log`) → appel à l'intérieur de `with_tenant`.
///
/// Zéro PII : `metadata` ne contient que `MSH-10` (identifiant de contrôle
/// choisi par l'émetteur, pas une donnée patient) et `MSH-9`, jamais
/// `PID-3`/`PID-5`.
async fn check_idempotency_and_audit(
    pool: &PgPool,
    cabinet_id: Uuid,
    partner_id: Uuid,
    control_id: &str,
    message_type: &str,
) -> Result<bool, core_tenancy::TenancyError> {
    let control_id = control_id.to_string();
    let message_type = message_type.to_string();

    with_tenant(pool, cabinet_id, move |mut tx| async move {
        let is_fresh: bool =
            sqlx::query_scalar("SELECT hl7v2_message_log_check_and_insert($1, $2)")
                .bind(partner_id)
                .bind(&control_id)
                .fetch_one(&mut *tx)
                .await?;

        if is_fresh {
            let action = format!("hl7v2_message_received:{message_type}");
            // entity_id reste NULL si MSH-10 n'est pas un UUID (cas le plus
            // fréquent : un ID de contrôle HL7 v2 est choisi librement par
            // l'émetteur) — la valeur textuelle reste dans `metadata`.
            let entity_id = Uuid::parse_str(&control_id).ok();
            let metadata = serde_json::json!({
                "message_control_id": control_id,
                "message_type": message_type,
            });

            sqlx::query(
                "INSERT INTO audit_log \
                 (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
                 VALUES ($1, $2, 'hl7v2_partner', $3, 'hl7v2_message', $4, $5)",
            )
            .bind(cabinet_id)
            .bind(partner_id)
            .bind(&action)
            .bind(entity_id)
            .bind(&metadata)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(is_fresh)
    })
    .await
}

/// ── Frontière métier ADT (B8) / SIU (B9) ── Seul ce `match` est à toucher
/// pour brancher/étendre le traitement, sans réécrire `dispatch()`.
///
/// `Err(detail)` → ACK `AE` avec `detail` en `MSA-3` (cf. [`RejectReason::ProcessingFailed`]).
/// `Ok(())` → ACK `AA`. Ne panique jamais : toute erreur (segment manquant,
/// UUID invalide, échec service) est convertie en `Err`, jamais un `unwrap`.
async fn process_message(
    pool: &PgPool,
    cabinet_id: Uuid,
    partner_id: Uuid,
    message: &Message,
    message_type: &str,
    key_manager: &dyn KeyManager,
) -> Result<(), String> {
    // Le groupe de message (avant `^`) suffit à distinguer ADT/SIU ; le
    // sous-type précis (A28, S12, ...) est discriminé dans chaque module.
    let message_group = message_type.split('^').next().unwrap_or(message_type);
    match message_group {
        "ADT" => {
            let trigger = message_type.split('^').nth(1).unwrap_or("");
            adt_patient::handle(pool, cabinet_id, key_manager, message, trigger)
                .await
                .map_err(|e| e.to_string())
        }
        "SIU" => siu::handle(pool, cabinet_id, partner_id, message, message_type)
            .await
            .map_err(|e| e.to_string()),
        _ => {
            tracing::debug!(
                message_type,
                "hl7v2 dispatch: type non géré, stub optimiste"
            );
            Ok(())
        }
    }
}

/// Champ MSH `n` (1-based) en `String` propriétaire (utile après un `return`
/// anticipé). `None` si `MSH` est absent ou le champ `n` inexistant — jamais
/// de panique.
fn msh_field(message: &Message, n: usize) -> Option<String> {
    message
        .segment("MSH")
        .and_then(|msh| msh.field(n))
        .map(str::to_string)
}

/// Construit un [`DispatchOutcome`] de rejet (`AR`, ou `AE` pour
/// [`RejectReason::Internal`]) ; l'ID de contrôle de l'ACK est généré ici (la
/// crate pure `integrations-hl7v2` ne génère ni horodatage ni aléa).
fn reject(control_id: &str, reason: RejectReason) -> DispatchOutcome {
    let code = match reason {
        RejectReason::Internal | RejectReason::ProcessingFailed(_) => AckCode::ApplicationError,
        RejectReason::UnknownOrInactivePartner | RejectReason::UnknownFacilityMapping => {
            AckCode::ApplicationReject
        }
    };
    let text = match &reason {
        RejectReason::UnknownOrInactivePartner => "partenaire inconnu ou inactif".to_string(),
        RejectReason::UnknownFacilityMapping => {
            "aucun cabinet associé à cet établissement émetteur/destinataire".to_string()
        }
        RejectReason::Internal => "erreur technique".to_string(),
        RejectReason::ProcessingFailed(detail) => detail.clone(),
    };
    let ack_control_id = Uuid::new_v4().to_string();
    let ack = build_ack(&AckParams {
        original_control_id: control_id,
        ack_control_id: &ack_control_id,
        code,
        text: Some(&text),
    });
    DispatchOutcome {
        status: DispatchStatus::Rejected(reason),
        ack,
    }
}

/// Construit un [`DispatchOutcome`] d'acceptation (`AA`), message frais ou
/// doublon déjà vu.
fn accept(control_id: &str, status: DispatchStatus) -> DispatchOutcome {
    let ack_control_id = Uuid::new_v4().to_string();
    let ack = build_ack(&AckParams {
        original_control_id: control_id,
        ack_control_id: &ack_control_id,
        code: AckCode::ApplicationAccept,
        text: None,
    });
    DispatchOutcome { status, ack }
}

#[cfg(test)]
mod tests {
    use super::*;
    use integrations_hl7v2::parser::parse;

    const ADT_A28: &str =
        "MSH|^~\\&|NUBIA|CABINET1|SIH|HOPITAL1|20260719101500||ADT^A28|MSGID0001|P|2.5\r\
PID|1||123456^^^HOPITAL1^PI||DUPONT^JEAN||19800101|M\r\
PV1|1|O\r";

    #[test]
    fn msh_field_extracts_facilities_type_and_control_id() {
        let msg = parse(ADT_A28).expect("message de test valide");
        assert_eq!(msh_field(&msg, 4).as_deref(), Some("CABINET1")); // sending
        assert_eq!(msh_field(&msg, 6).as_deref(), Some("HOPITAL1")); // receiving
        assert_eq!(msh_field(&msg, 9).as_deref(), Some("ADT^A28")); // type
        assert_eq!(msh_field(&msg, 10).as_deref(), Some("MSGID0001")); // control id
        assert_eq!(msh_field(&msg, 999), None); // hors limites -> None, pas de panique
    }

    #[test]
    fn reject_builds_ar_ack_and_echoes_control_id() {
        let outcome = reject("MSGID0001", RejectReason::UnknownOrInactivePartner);
        assert_eq!(
            outcome.status,
            DispatchStatus::Rejected(RejectReason::UnknownOrInactivePartner)
        );
        let reparsed = parse(&outcome.ack).expect("ack généré doit se re-parser");
        let msa = reparsed.segment("MSA").expect("MSA présent");
        assert_eq!(msa.field(1), Some("AR"));
        assert_eq!(msa.field(2), Some("MSGID0001"));
    }

    #[test]
    fn reject_internal_builds_ae_ack() {
        let outcome = reject("MSGID0002", RejectReason::Internal);
        let reparsed = parse(&outcome.ack).expect("ack généré doit se re-parser");
        assert_eq!(
            reparsed.segment("MSA").expect("MSA présent").field(1),
            Some("AE")
        );
    }

    #[test]
    fn accept_builds_aa_ack_for_both_accepted_and_duplicate_status() {
        let partner_id = Uuid::new_v4();
        let cabinet_id = Uuid::new_v4();

        let accepted = accept(
            "MSGID0003",
            DispatchStatus::Accepted {
                partner_id,
                cabinet_id,
            },
        );
        let reparsed = parse(&accepted.ack).expect("ack généré doit se re-parser");
        assert_eq!(reparsed.segment("MSA").unwrap().field(1), Some("AA"));

        let duplicate = accept(
            "MSGID0003",
            DispatchStatus::Duplicate {
                partner_id,
                cabinet_id,
            },
        );
        assert_eq!(
            duplicate.status,
            DispatchStatus::Duplicate {
                partner_id,
                cabinet_id
            }
        );
        let reparsed_dup = parse(&duplicate.ack).expect("ack généré doit se re-parser");
        assert_eq!(reparsed_dup.segment("MSA").unwrap().field(1), Some("AA"));
    }

    /// Pool jamais connecté (`connect_lazy`) : suffisant pour un type non géré
    /// (stub optimiste, ne touche jamais `pool`) — pas de DB requise. Le
    /// traitement ADT réel (qui, lui, a besoin d'une vraie DB dès qu'un PID
    /// valide est fourni) est couvert par les tests unitaires de
    /// `interop::patient` et le test e2e (lot B11) ; ici on vérifie
    /// seulement qu'un ADT sans PID échoue proprement (`Err`), sans jamais
    /// paniquer ni toucher `pool`.
    fn lazy_pool() -> PgPool {
        sqlx::postgres::PgPoolOptions::new()
            .connect_lazy("postgres://fake@localhost/fake")
            .expect("connect_lazy ne doit jamais échouer (aucune connexion tentée)")
    }

    #[tokio::test]
    async fn process_message_adt_without_pid_fails_cleanly_and_unknown_is_noop() {
        let pool = lazy_pool();
        let partner_id = Uuid::new_v4();
        let cabinet_id = Uuid::new_v4();
        let key_manager = core_crypto::LocalKeyManager::new([3u8; 32], "test-v1");
        let msg = parse("MSH|^~\\&|A|B|C|D|20260719||ADT^A28|1|P|2.5\r").unwrap();

        // Pas de segment PID : échoue avant tout accès DB, jamais de panique.
        assert!(
            process_message(&pool, cabinet_id, partner_id, &msg, "ADT^A28", &key_manager)
                .await
                .is_err()
        );

        let unknown = parse("MSH|^~\\&|A|B|C|D|20260719||ZZZ^Z99|1|P|2.5\r").unwrap();
        assert_eq!(
            process_message(
                &pool,
                cabinet_id,
                partner_id,
                &unknown,
                "ZZZ^Z99",
                &key_manager
            )
            .await,
            Ok(()) // type non géré : reste un no-op sûr
        );
    }
}
