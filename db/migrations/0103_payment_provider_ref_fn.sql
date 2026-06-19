-- 0103_payment_provider_ref_fn.sql
-- Fonction SECURITY DEFINER permettant aux handlers webhook (nubia_app) de lire
-- cabinet_id + payment.id depuis provider_ref sans être bloqués par la RLS
-- tenant_isolation (qui filtre par app.current_cabinet_id).
--
-- Problème : les webhooks Stripe/GoCardless arrivent hors contexte JWT — il n'y a
-- pas de cabinet_id connu à l'avance. Le handler doit d'abord lire le cabinet_id
-- depuis payment (pour ensuite poser le GUC et faire l'UPDATE), mais la policy
-- tenant_isolation bloque ce SELECT quand le GUC est vide ou nil.
--
-- Solution : une fonction SECURITY DEFINER (exécutée avec les droits nubia_owner,
-- qui a BYPASSRLS) retourne (id, cabinet_id) pour un (provider, provider_ref) donné.
-- Elle est strictement en lecture (STABLE), search_path figé (sécurité), pas de DDL.
--
-- Réf. : pattern identique pour refresh_token_owner (migration 0066).

CREATE OR REPLACE FUNCTION payment_find_by_provider_ref(
    p_provider     text,
    p_provider_ref text
)
RETURNS TABLE(id uuid, cabinet_id uuid)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
    SELECT id, cabinet_id
    FROM payment
    WHERE provider = p_provider
      AND provider_ref = p_provider_ref
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION payment_find_by_provider_ref(text, text) TO nubia_app;
