-- 0122_user_pharmacy_memberships_fn.sql
-- Fonction SECURITY DEFINER qui retourne les memberships pharmacie actifs d'un
-- utilisateur, en contournant la RLS pharmacy-scoped (nécessaire pour
-- POST /v1/auth/select-pharmacy-context avec un token login sans pharmacy_id).
-- Pattern identique à user_all_memberships (migration 0089).
-- Issue : #3306

CREATE OR REPLACE FUNCTION user_pharmacy_memberships(p_user_id uuid)
    RETURNS TABLE(pharmacy_id uuid, role text)
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT
        pm.pharmacy_id,
        pm.role
    FROM pharmacy_membership pm
    WHERE pm.user_id = p_user_id
      AND pm.active  = true
    ORDER BY pm.created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION user_pharmacy_memberships(uuid) TO nubia_app;
