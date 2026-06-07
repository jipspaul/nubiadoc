-- 0083_user_active_membership_fn.sql
-- Fonction SECURITY DEFINER qui retourne (cabinet_id, role) du premier membership
-- actif d'un utilisateur pro, en contournant la RLS cabinet-scoped.
-- Nécessaire pour le handler login : au moment de l'authentification, on connaît
-- le user_id mais pas encore le cabinet_id (requis par la policy tenant_isolation
-- sur cabinet_membership). Modèle identique à refresh_token_owner (migration 0066).
-- Issue : #1084

CREATE OR REPLACE FUNCTION user_active_membership(p_user_id uuid)
    RETURNS TABLE(cabinet_id uuid, role text)
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT cabinet_id, role
    FROM cabinet_membership
    WHERE user_id = p_user_id
      AND active = true
    ORDER BY created_at ASC
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION user_active_membership(uuid) TO nubia_app;
