-- 0065_refresh_token_owner_fn.sql
-- Fonction SECURITY DEFINER qui retourne l'app_user_id d'un refresh_token
-- par son hash, en contournant la RLS user-scoped.
-- Nécessaire pour le handler logout : vérifier qu'un token appartient bien
-- à l'utilisateur authentifié avant révocation, sans que la policy
-- token_user_select ne masque les tokens d'autres utilisateurs.
-- Issue : #794

CREATE OR REPLACE FUNCTION refresh_token_owner(p_token_hash text)
    RETURNS uuid
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT app_user_id FROM refresh_token WHERE token_hash = p_token_hash;
$$;

GRANT EXECUTE ON FUNCTION refresh_token_owner(text) TO nubia_app;
