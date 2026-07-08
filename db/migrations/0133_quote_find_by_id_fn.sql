-- 0133_quote_find_by_id_fn.sql
-- Fonction SECURITY DEFINER permettant au handler webhook Yousign (nubia_app) de
-- lire cabinet_id depuis quote.id sans être bloqué par la RLS tenant_isolation
-- (qui filtre par app.current_cabinet_id).
--
-- Problème : le webhook Yousign arrive hors contexte JWT — il n'y a pas de
-- cabinet_id connu à l'avance. Le handler doit d'abord lire le cabinet_id
-- depuis quote (pour ensuite poser le GUC et faire l'UPDATE), mais la policy
-- tenant_isolation bloque ce SELECT quand le GUC est vide ou nil : la ligne
-- reste invisible et le webhook ne trouve jamais le devis (`quote not found`).
--
-- Solution : même pattern que payment_find_by_provider_ref (migration 0103) —
-- une fonction SECURITY DEFINER (exécutée avec les droits nubia_owner, qui a
-- BYPASSRLS) retourne cabinet_id pour un quote.id donné.

CREATE OR REPLACE FUNCTION quote_find_by_id(
    p_id uuid
)
RETURNS TABLE(cabinet_id uuid)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT cabinet_id
    FROM quote
    WHERE id = p_id
      AND deleted_at IS NULL
$$;

GRANT EXECUTE ON FUNCTION quote_find_by_id(uuid) TO nubia_app;
