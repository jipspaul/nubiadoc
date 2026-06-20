-- 0104_is_clinical_role.sql
-- Fonction utilitaire : teste si un rôle cabinet est "clinique" (accès aux données de santé).
-- Utilisée dans les policies RLS qui cloisonnent l'accès praticien/assistant clinique
-- vs secrétariat/admin.
-- Issue : #2235

CREATE OR REPLACE FUNCTION is_clinical_role(role_text text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(role_text IN ('practitioner', 'assistant_clinical'), false);
$$;

COMMENT ON FUNCTION is_clinical_role(text) IS
  'Retourne true si role_text est un rôle clinique (practitioner, assistant_clinical). '
  'Retourne false pour tout autre rôle (secretariat, admin) et pour NULL.';
