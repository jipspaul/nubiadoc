-- 0178_merge_patient_fn.sql
-- merge_patient(source_id, target_id) : aucun mécanisme de fusion de
-- doublons n'existait (#4101). Réattribue vers le patient cible TOUTES les
-- tables référençant patient(id) — recensement exhaustif du schéma à date
-- (16 tables), pas seulement les 4 citées en exemple par l'issue
-- (appointment/document/quote/clinical_note) :
--   medical_record, clinical_note, dental_chart, document, appointment,
--   waiting_list_entry, quote, payment_schedule, payment, conversation,
--   treatment_plan, prescription, consultation_act, implant_passport,
--   reminder, patient_tag.
-- Puis soft-delete la fiche source (patient.deleted_at).
--
-- Exclusion délibérée : audit_log. `entity_id` y est un UUID libre non
-- contraint par FK (paire polymorphe entity/entity_id) et la table est
-- append-only (0008 : nubia_app n'a que INSERT, jamais UPDATE) — réécrire
-- l'historique d'audit falsifierait le journal. Le merge lui-même est
-- audité (action='merge_patient') plutôt que de modifier les entrées
-- passées.
--
-- Deux tables ont une contrainte d'unicité sur patient_id qu'une simple
-- UPDATE peut violer si le patient cible a déjà une ligne équivalente :
--   - dental_chart (UNIQUE patient_id, cabinet_id, 0081) : si le patient
--     cible a déjà un schéma dentaire, celui du patient source N'EST PAS
--     réattribué (reste sous le patient source, soft-supprimé mais
--     récupérable en base — jamais perdu, juste plus visible normalement).
--     Écraser un schéma dentaire existant sans arbitrage humain serait une
--     perte de donnée clinique.
--   - waiting_list_entry (UNIQUE partiel patient_id+provider_id WHERE
--     active, 0096) : l'entrée active du patient source en conflit avec
--     une entrée active du patient cible (même provider) est annulée
--     (status='cancelled') avant réattribution des autres lignes — pas de
--     perte, juste plus de doublon actif.
--
-- SECURITY DEFINER + row_security=off (même pattern que
-- resolve_slot_for_booking, 0128) : la fusion touche des lignes hors du
-- scope RLS d'une seule transaction cabinet (mais source/cible doivent
-- être dans LE MÊME cabinet, vérifié explicitement — pas de fusion
-- cross-tenant).
-- Issue : #4101

CREATE OR REPLACE FUNCTION merge_patient(
    p_source_id uuid,
    p_target_id uuid
) RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET row_security = off
    SET search_path = public
AS $$
DECLARE
    v_source_cabinet_id uuid;
    v_source_deleted_at timestamptz;
    v_target_cabinet_id uuid;
    v_target_deleted_at timestamptz;
BEGIN
    IF p_source_id = p_target_id THEN
        RAISE EXCEPTION 'merge_patient: source and target must differ';
    END IF;

    SELECT cabinet_id, deleted_at INTO v_source_cabinet_id, v_source_deleted_at
      FROM patient WHERE id = p_source_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'merge_patient: source patient % not found', p_source_id;
    END IF;
    IF v_source_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'merge_patient: source patient % already deleted', p_source_id;
    END IF;

    SELECT cabinet_id, deleted_at INTO v_target_cabinet_id, v_target_deleted_at
      FROM patient WHERE id = p_target_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'merge_patient: target patient % not found', p_target_id;
    END IF;
    IF v_target_deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'merge_patient: target patient % already deleted', p_target_id;
    END IF;

    IF v_source_cabinet_id <> v_target_cabinet_id THEN
        RAISE EXCEPTION 'merge_patient: source and target must belong to the same cabinet';
    END IF;

    -- Tables sans contrainte d'unicité sur patient_id : réattribution directe.
    UPDATE medical_record     SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE clinical_note      SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE document           SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE appointment        SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE quote              SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE payment_schedule   SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE payment            SET patient_id = p_target_id WHERE patient_id = p_source_id;
    -- conversation.patient_id nullable (0036) : les lignes scope
    -- 'platform_support' ont patient_id NULL par construction, jamais
    -- égal à p_source_id — exclues naturellement par le WHERE.
    UPDATE conversation       SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE treatment_plan     SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE prescription       SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE consultation_act   SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE implant_passport   SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE reminder           SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE patient_tag        SET patient_id = p_target_id WHERE patient_id = p_source_id;

    -- dental_chart : UNIQUE(patient_id, cabinet_id) — ne réattribue que si
    -- le patient cible n'a pas déjà de schéma dentaire.
    UPDATE dental_chart
       SET patient_id = p_target_id
     WHERE patient_id = p_source_id
       AND NOT EXISTS (
             SELECT 1 FROM dental_chart WHERE patient_id = p_target_id
           );

    -- waiting_list_entry : annule le doublon actif (même provider) avant
    -- réattribution du reste.
    UPDATE waiting_list_entry wl
       SET status = 'cancelled'
     WHERE wl.patient_id = p_source_id
       AND wl.status = 'active'
       AND EXISTS (
             SELECT 1 FROM waiting_list_entry t
              WHERE t.patient_id = p_target_id
                AND t.provider_id = wl.provider_id
                AND t.status = 'active'
           );
    UPDATE waiting_list_entry SET patient_id = p_target_id WHERE patient_id = p_source_id;

    -- Fiche source : soft-delete (jamais de suppression physique).
    UPDATE patient SET deleted_at = now() WHERE id = p_source_id;
END;
$$;

GRANT EXECUTE ON FUNCTION merge_patient(uuid, uuid) TO nubia_app;
