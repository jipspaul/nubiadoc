-- 0149_hl7v2_partner_facility_map_find_cabinet.sql
-- Complète 0148 (lot B6) : le dispatch HL7v2 (lot B7, api/src/hl7v2/dispatch.rs)
-- doit résoudre le cabinet_id cible à partir de (partner_id, MSH-4, MSH-6)
-- AVANT tout contexte tenant connu (c'est justement ce couple qui détermine
-- quel cabinet — donc quel GUC app.current_cabinet_id poser). 0148 fournissait
-- déjà hl7v2_partner_find_by_fingerprint (résolution partenaire) et
-- hl7v2_message_log_check_and_insert (dédup), mais pas cette résolution
-- facility -> cabinet : lot B7 l'avait anticipée sous le nom
-- hl7v2_partner_facility_map_find_cabinet(uuid, text, text), documentée
-- "ASSOMPTION (B6), à confirmer au merge" dans son propre code. Cette
-- migration ajoute exactement cette fonction, sans toucher 0148.
--
-- Forme SQL : `RETURNS TABLE(cabinet_id uuid)` (pas `RETURNS uuid`) — B7
-- l'appelle via `SELECT cabinet_id FROM hl7v2_partner_facility_map_find_cabinet(...)`,
-- ce qui exige que la colonne de sortie s'appelle explicitement `cabinet_id`
-- (un `RETURNS uuid` nommerait la colonne d'après la fonction elle-même, pas
-- `cabinet_id` — ça ne matcherait pas la requête déjà écrite côté Rust).
--
-- SECURITY DEFINER, STABLE, search_path figé : même pattern que
-- hl7v2_partner_find_by_fingerprint (0148) et payment_find_by_provider_ref
-- (0103). Le couple (partner_id, sending_facility, receiving_facility) est
-- UNIQUE dans hl7v2_partner_facility_map (contrainte posée en 0148) : au plus
-- une ligne en sortie.
CREATE OR REPLACE FUNCTION hl7v2_partner_facility_map_find_cabinet(
    p_partner_id uuid,
    p_sending_facility text,
    p_receiving_facility text
)
    RETURNS TABLE(cabinet_id uuid)
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT m.cabinet_id
    FROM hl7v2_partner_facility_map m
    WHERE m.partner_id = p_partner_id
      AND m.sending_facility = p_sending_facility
      AND m.receiving_facility = p_receiving_facility;
$$;

GRANT EXECUTE ON FUNCTION hl7v2_partner_facility_map_find_cabinet(uuid, text, text) TO nubia_app;
