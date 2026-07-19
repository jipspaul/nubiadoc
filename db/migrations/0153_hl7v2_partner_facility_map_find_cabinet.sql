-- 0153_hl7v2_partner_facility_map_find_cabinet.sql
-- Complète 0151 (lot B6, ex-0148) : le dispatch HL7v2 (lot B7,
-- api/src/hl7v2/dispatch.rs, déjà mergé sur main) appelle
-- `hl7v2_partner_facility_map_find_cabinet(partner_id, sending_facility,
-- receiving_facility)` pour résoudre le cabinet cible avant tout contexte
-- tenant connu (c'est justement ce couple qui détermine quel cabinet — donc
-- quel GUC app.current_cabinet_id poser). Cette fonction n'existait pas
-- encore : gap découvert et comblé ici.
--
-- Forme SQL : `RETURNS TABLE(cabinet_id uuid)` (pas `RETURNS uuid`) — le code
-- Rust l'appelle via `SELECT cabinet_id FROM
-- hl7v2_partner_facility_map_find_cabinet(...)`, ce qui exige que la colonne
-- de sortie s'appelle explicitement `cabinet_id` (un `RETURNS uuid` nommerait
-- la colonne d'après la fonction elle-même, pas `cabinet_id`).
--
-- SECURITY DEFINER, STABLE, search_path figé : même pattern que
-- hl7v2_partner_find_by_fingerprint (0151) et payment_find_by_provider_ref
-- (0103). Le couple (partner_id, sending_facility, receiving_facility) est
-- UNIQUE dans hl7v2_partner_facility_map (contrainte posée en 0151) : au plus
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
