-- 0162_cabinet_membership_valid_until.sql
-- cabinet_membership.role ne distingue pas les remplaçants/collaborateurs
-- temporaires des titulaires permanents — aucun accès borné dans le temps,
-- alors que la « gestion des remplaçants » est citée par le référentiel
-- comme un détail qui « tue une démo » (§4.3, #4157).
--
-- Ajoute valid_until (nullable — NULL = accès permanent, comportement
-- inchangé pour tous les membership existants). La borne est appliquée au
-- SEUL point d'authentification qui résout les memberships d'un utilisateur
-- pro en base : user_all_memberships() (migration 0089, SECURITY DEFINER),
-- appelée par POST /v1/auth/login (fast-path mono-cabinet) ET
-- POST /v1/auth/select-context (émission du JWT scopé cabinet_id/role). Un
-- membership expiré n'est simplement plus retourné par la fonction → même
-- chemin d'erreur existant (403 no_membership côté select-context, ou
-- absence de contexte mono-cabinet côté login), aucun changement Rust requis.
--
-- user_active_membership (migration 0083) n'est appelée par aucun code Rust
-- (fonction commentée comme référence de design par 0089/0147, jamais
-- invoquée) — non modifiée, hors scope.

ALTER TABLE cabinet_membership ADD COLUMN IF NOT EXISTS valid_until timestamptz;

COMMENT ON COLUMN cabinet_membership.valid_until IS
    'Borne de fin d''accès (remplaçants/collaborateurs temporaires, #4157). '
    'NULL = accès permanent. Appliquée par user_all_memberships().';

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
      AND (cm.valid_until IS NULL OR cm.valid_until > now())
    ORDER BY cm.created_at ASC;
$$;
