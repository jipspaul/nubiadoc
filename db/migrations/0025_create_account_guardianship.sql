-- 0025_create_account_guardianship.sql
-- Ajustements table account_guardianship (créée en 0010) — issue #239.
-- + updated_at, défaut authority='full', index partiel WHERE active=true,
--   RLS guardian-scoped (GUC app.current_account_id).

-- 1. Colonne updated_at absente de 0010
ALTER TABLE account_guardianship
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- 2. Défaut authority : spec issue #239 impose 'full' (0010 avait 'legal_guardian')
ALTER TABLE account_guardianship
  ALTER COLUMN authority SET DEFAULT 'full';

-- 3. Remplace la contrainte UNIQUE non-partielle par un index partiel WHERE active=true.
--    Un même guardian/dependent peut avoir plusieurs lignes si la précédente est révoquée
--    (active=false), ce que la contrainte full empêchait.
ALTER TABLE account_guardianship
  DROP CONSTRAINT IF EXISTS "account_guardianship_guardian_account_id_dependent_account__key";
CREATE UNIQUE INDEX IF NOT EXISTS account_guardianship_active_pair_uidx
  ON account_guardianship (guardian_account_id, dependent_account_id)
  WHERE active = true;

-- 4. RLS guardian-scoped (entité plateforme — pas de cabinet_id).
--    SELECT borné au compte courant (guardian ou dependent) via app.current_account_id.
--    INSERT / UPDATE / DELETE non filtrés par RLS (contrôle applicatif via X-On-Behalf-Of).
ALTER TABLE account_guardianship ENABLE ROW LEVEL SECURITY;

-- nubia_app : SELECT visible uniquement pour le guardian ou le dependent du compte courant
CREATE POLICY guardianship_owner_select ON account_guardianship
  FOR SELECT TO nubia_app
  USING (
    guardian_account_id  = nullif(current_setting('app.current_account_id', true), '')::uuid
    OR
    dependent_account_id = nullif(current_setting('app.current_account_id', true), '')::uuid
  );

-- nubia_app : écriture sans restriction RLS (droit d'accès géré par l'API)
CREATE POLICY guardianship_app_insert ON account_guardianship
  FOR INSERT TO nubia_app
  WITH CHECK (true);

CREATE POLICY guardianship_app_update ON account_guardianship
  FOR UPDATE TO nubia_app
  USING (true) WITH CHECK (true);

CREATE POLICY guardianship_app_delete ON account_guardianship
  FOR DELETE TO nubia_app
  USING (true);

-- nubia_seed : accès complet (données de démo fictives)
CREATE POLICY guardianship_seed ON account_guardianship
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);
