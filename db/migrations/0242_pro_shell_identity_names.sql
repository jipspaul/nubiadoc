-- 0242_pro_shell_identity_names.sql
-- Le shell pro (#6170, même cause que #6165) n'affiche jamais qui est
-- connecté ni dans quel cabinet/pharmacie : GET /v1/me expose cabinet_id et
-- pharmacy_id mais jamais leur nom, alors que user_all_memberships() /
-- user_pharmacy_memberships() (SECURITY DEFINER, seules fonctions autorisées
-- à lire cabinet/pharmacy hors GUC tenant) pourraient le joindre directement.
-- Signature d'entrée inchangée (p_user_id uuid) : DROP requis (pas
-- CREATE OR REPLACE) uniquement parce que le type de retour gagne une
-- colonne — tous les appelants existants (login.rs, refresh.rs, register.rs,
-- select_context.rs, select_pharmacy_context.rs) listent leurs colonnes
-- explicitement et ne sont pas affectés par l'ajout.

DROP FUNCTION IF EXISTS user_all_memberships(uuid);

CREATE FUNCTION user_all_memberships(p_user_id uuid)
    RETURNS TABLE(cabinet_id uuid, role text, secretariat_id uuid, cabinet_name text)
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT
        cm.cabinet_id,
        cm.role,
        sm.secretariat_id,
        c.raison_sociale
    FROM cabinet_membership cm
    JOIN cabinet c
        ON c.id = cm.cabinet_id
    LEFT JOIN secretariat_membership sm
        ON sm.cabinet_id  = cm.cabinet_id
       AND sm.user_id     = cm.user_id
       AND sm.active      = true
    WHERE cm.user_id = p_user_id
      AND cm.active  = true
      AND (cm.valid_until IS NULL OR cm.valid_until > now())
    ORDER BY cm.created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION user_all_memberships(uuid) TO nubia_app;

DROP FUNCTION IF EXISTS user_pharmacy_memberships(uuid);

CREATE FUNCTION user_pharmacy_memberships(p_user_id uuid)
    RETURNS TABLE(pharmacy_id uuid, role text, pharmacy_name text)
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT
        pm.pharmacy_id,
        pm.role,
        p.raison_sociale
    FROM pharmacy_membership pm
    JOIN pharmacy p
        ON p.id = pm.pharmacy_id
    WHERE pm.user_id = p_user_id
      AND pm.active  = true
    ORDER BY pm.created_at ASC;
$$;

GRANT EXECUTE ON FUNCTION user_pharmacy_memberships(uuid) TO nubia_app;
