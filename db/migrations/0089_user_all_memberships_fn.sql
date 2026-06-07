-- 0089_user_all_memberships_fn.sql
-- Fonction SECURITY DEFINER qui retourne tous les memberships actifs d'un utilisateur pro,
-- en contournant la RLS cabinet-scoped (nécessaire pour GET /v1/me avec un token login
-- qui ne porte pas de cabinet_id). Retourne (cabinet_id, role, secretariat_id nullable).
-- Pattern identique à user_active_membership (migration 0083) mais sans LIMIT 1.
-- Issue : #1227

CREATE OR REPLACE FUNCTION user_all_memberships(p_user_id uuid)
    RETURNS TABLE(cabinet_id uuid, role text, secretariat_id uuid)
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT
        cm.cabinet_id,
        cm.role,
        sm.secretariat_id
    FROM cabinet_membership cm
    LEFT JOIN secretariat_membership sm
        ON sm.cabinet_id  = cm.cabinet_id
       AND sm.user_id     = cm.user_id
       AND sm.active      = true
    WHERE cm.user_id = p_user_id
      AND cm.active  = true
    ORDER BY cm.created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION user_all_memberships(uuid) TO nubia_app;
