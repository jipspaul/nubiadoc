-- 0147_device_reassign_token_fn.sql
-- Fonction SECURITY DEFINER qui invalide (soft-delete) toute ligne `device`
-- ACTIVE d'un AUTRE utilisateur partageant le même fcm_token, en contournant
-- la RLS user-scoped (policy device_owner, migration 0052) qui empêche
-- nubia_app de voir/modifier les devices d'un autre app_user_id.
-- Nécessaire : un fcm_token identifie UN install physique ; le réenregistrer
-- sous un nouvel utilisateur (terminal réattribué/partagé) doit invalider la
-- ligne du précédent propriétaire, sinon le worker push lui livre les
-- notifications de l'ancien compte. Modèle identique à user_active_membership
-- (migration 0083). Issue : #3789

CREATE OR REPLACE FUNCTION device_deactivate_other_owners(p_fcm_token text, p_current_user_id uuid)
    RETURNS void
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path = public
AS $$
    UPDATE device SET deleted_at = now()
    WHERE fcm_token = p_fcm_token
      AND app_user_id != p_current_user_id
      AND deleted_at IS NULL;
$$;

GRANT EXECUTE ON FUNCTION device_deactivate_other_owners(text, uuid) TO nubia_app;
