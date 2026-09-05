-- 0254_user_practitioner_ids_fn.sql
-- RÉCIDIVE #6504 de #6446 : le correctif #6251 (GET /v1/me expose
-- `practitioner_id` par cabinet) interroge directement `practitioner` :
--   SELECT cabinet_id, id FROM practitioner WHERE user_id = $1
-- Or `practitioner` est une table tenant, RLS fail-closed FORCE (migration
-- 0011, policy `cabinet_id = current_setting('app.current_cabinet_id')`).
-- Cette requête tourne sur une connexion `nubia_app` nue, sans
-- `app.current_cabinet_id` posé (l'utilisateur peut appartenir à plusieurs
-- cabinets, il n'y a pas UN cabinet à poser en GUC avant de résoudre la
-- correspondance) : la policy ne matche jamais, 0 ligne, `practitioner_id`
-- toujours `None` — exactement le symptôme, quel que soit le cabinet.
-- Même pattern que `user_all_memberships` (migration 0089, 0242) et
-- `user_pharmacy_memberships` (migration 0122) : fonction SECURITY DEFINER
-- dédiée, contourne la RLS cabinet-scoped pour cette résolution multi-cabinet.

CREATE FUNCTION user_practitioner_ids(p_user_id uuid)
    RETURNS TABLE(cabinet_id uuid, practitioner_id uuid)
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT cabinet_id, id AS practitioner_id
    FROM practitioner
    WHERE user_id = p_user_id;
$$;

GRANT EXECUTE ON FUNCTION user_practitioner_ids(uuid) TO nubia_app;
