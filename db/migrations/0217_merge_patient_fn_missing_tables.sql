-- 0217_merge_patient_fn_missing_tables.sql
-- merge_patient (0178) n'a jamais été redéfinie depuis : 4 tables
-- `patient_id NOT NULL REFERENCES patient(id)` ajoutées après coup en sont
-- absentes et restent donc rattachées à la fiche source (soft-supprimée
-- après le merge) — perte de visibilité clinique côté fiche cible (#4582) :
--   - periodontal_chart      (0179) — aucune contrainte d'unicité.
--   - dental_chart_history   (0185) — append-only, mais patient_id reste
--     un simple UPDATE (pas d'UPDATE/DELETE de la ligne elle-même).
--   - orthodontic_treatment  (0189) — aucune contrainte d'unicité.
--   - lab_work_order         (0193) — FK composite (patient_id, cabinet_id) ;
--     source et cible sont garantis dans le même cabinet (vérifié plus
--     haut dans la fonction), donc l'UPDATE ne viole pas la FK.
-- Migrations forward-only (db/AGENTS.md) : on ne réécrit pas 0178, on
-- redéfinit la fonction avec CREATE OR REPLACE.

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
    UPDATE medical_record       SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE clinical_note        SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE document              SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE appointment           SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE quote                 SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE payment_schedule      SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE payment               SET patient_id = p_target_id WHERE patient_id = p_source_id;
    -- conversation.patient_id nullable (0036) : les lignes scope
    -- 'platform_support' ont patient_id NULL par construction, jamais
    -- égal à p_source_id — exclues naturellement par le WHERE.
    UPDATE conversation          SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE treatment_plan        SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE prescription          SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE consultation_act      SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE implant_passport      SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE reminder              SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE patient_tag           SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE periodontal_chart     SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE dental_chart_history  SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE orthodontic_treatment SET patient_id = p_target_id WHERE patient_id = p_source_id;
    UPDATE lab_work_order        SET patient_id = p_target_id WHERE patient_id = p_source_id;

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
