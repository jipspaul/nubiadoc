-- 0155_ensure_patient_for_cabinet_resync_name.sql
-- ensure_patient_for_cabinet (0123) est un get-or-create : au premier appel,
-- il copie first_name/last_name depuis patient_account. Si le patient réserve
-- AVANT d'avoir complété son profil (patient_account.first_name/last_name
-- encore '' à l'inscription, cf. auth/register.rs), la fiche patient du
-- cabinet est créée avec un nom vide — et n'est JAMAIS re-synchronisée
-- ensuite, même après que le patient renseigne son nom via PATCH /account.
-- Le soignant voit alors une fiche définitivement anonyme (avatar « ? »/« – »).
--
-- Sur la branche "déjà existante", resynchronise désormais first_name/
-- last_name depuis patient_account — seulement si la source a un nom non vide
-- ET diffère de la copie cabinet (no-op sinon, pas d'UPDATE inutile à chaque
-- réservation). patient.first_name/last_name n'est jamais édité
-- indépendamment par le cabinet pour un patient lié à un compte (aucun
-- endpoint PATCH ne le fait) : la source de vérité est toujours
-- patient_account, resynchroniser ne peut donc pas écraser une correction
-- saisie par le staff.
-- Issue : #3895

DROP FUNCTION IF EXISTS ensure_patient_for_cabinet(uuid, uuid);

CREATE FUNCTION ensure_patient_for_cabinet(p_account_id uuid, p_cabinet_id uuid)
  RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id
    FROM patient
    WHERE patient_account_id = p_account_id
      AND cabinet_id = p_cabinet_id
      AND deleted_at IS NULL
    LIMIT 1;
  IF v_id IS NOT NULL THEN
    UPDATE patient p
      SET first_name = pa.first_name,
          last_name  = pa.last_name
      FROM patient_account pa
      WHERE p.id = v_id
        AND pa.id = p_account_id
        AND (pa.first_name <> '' OR pa.last_name <> '')
        AND (p.first_name <> pa.first_name OR p.last_name <> pa.last_name);
    RETURN v_id;
  END IF;

  INSERT INTO patient (cabinet_id, patient_account_id, app_user_id,
                       first_name, last_name, birth_date, contact)
  SELECT p_cabinet_id, pa.id, pa.app_user_id,
         pa.first_name, pa.last_name, pa.birth_date, pa.contact
    FROM patient_account pa
    WHERE pa.id = p_account_id AND pa.deleted_at IS NULL
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

ALTER FUNCTION ensure_patient_for_cabinet(uuid, uuid) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION ensure_patient_for_cabinet(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ensure_patient_for_cabinet(uuid, uuid) TO nubia_app;
