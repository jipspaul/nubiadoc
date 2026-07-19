-- 0149_reactivate_cabinet_member_fn.sql
-- Fonction SECURITY DEFINER qui résout la ré-invitation d'un membre de cabinet
-- retiré (soft-delete). `post_cabinet_members` ne peut pas, sous RLS nubia_app,
-- retrouver un `app_user` existant par email (policy user_self_select restreint
-- au propre id) ; toute violation d'unicité sur `app_user.email` est donc mappée
-- en 409 member_already_exists à vie, même quand le membre a été retiré
-- (cabinet_membership.active=false) — aucun chemin de réactivation n'existait.
-- Cette fonction, appelée avant l'INSERT app_user, contourne la RLS pour :
--   - retrouver un compte pro existant par email ;
--   - si son adhésion à CE cabinet est inactive, la réactiver (active=true,
--     left_at=NULL, role mis à jour) ;
--   - si son adhésion à CE cabinet est déjà active, signaler le vrai conflit.
-- Un email lié à un compte SANS adhésion à ce cabinet reste hors scope (0 ligne
-- retournée, flux INSERT normal inchangé — invitation cross-cabinet non supportée,
-- cf. commentaire post_cabinet_members). Issue : #3878

CREATE OR REPLACE FUNCTION reactivate_cabinet_member(
    p_cabinet_id uuid,
    p_email text,
    p_role text
) RETURNS TABLE(matched_user_id uuid, already_active boolean)
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
AS $$
DECLARE
    v_user_id uuid;
    v_active boolean;
BEGIN
    SELECT id INTO v_user_id FROM app_user WHERE email = p_email AND kind = 'pro';
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    SELECT active INTO v_active FROM cabinet_membership
      WHERE cabinet_id = p_cabinet_id AND user_id = v_user_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    IF v_active THEN
        matched_user_id := v_user_id;
        already_active := true;
        RETURN NEXT;
        RETURN;
    END IF;

    UPDATE cabinet_membership
       SET active = true, left_at = NULL, role = p_role
     WHERE cabinet_id = p_cabinet_id AND user_id = v_user_id;

    matched_user_id := v_user_id;
    already_active := false;
    RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION reactivate_cabinet_member(uuid, text, text) TO nubia_app;
