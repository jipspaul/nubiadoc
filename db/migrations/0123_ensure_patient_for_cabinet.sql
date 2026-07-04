-- 0123_ensure_patient_for_cabinet.sql
-- Corrige le 404 sur POST /v1/bookings lors d'une réservation marketplace.
--
-- Le handler `create_booking` exigeait une fiche `patient` préexistante pour
-- (patient_account_id, cabinet_id). Or, quand un patient réserve chez un
-- praticien où il n'a jamais consulté (cas normal d'une réservation marketplace
-- chez un nouveau cabinet), cette fiche n'existe pas → `AppError::NotFound`
-- → 404 → « Erreur lors de la réservation du rendez-vous » côté app.
--
-- Cette fonction SECURITY DEFINER (owner nubia_owner, BYPASSRLS) récupère-ou-crée
-- le dossier patient du cabinet à la volée depuis `patient_account`. Retourne
-- NULL si le compte n'existe pas (le handler traduit alors en 404 légitime).
-- Contourne la RLS write sur `patient` (créée par le cabinet en temps normal).

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
