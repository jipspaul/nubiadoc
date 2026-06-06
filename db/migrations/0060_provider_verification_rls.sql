-- 0060_provider_verification_rls.sql
-- Ajoute cabinet_id à provider_verification (dérivé de provider) et active la RLS.
-- provider_verification est une table tenant : elle porte des données sensibles sur
-- le processus de vérification RPPS/ADELI d'un praticien rattaché à un cabinet.
-- Sans cabinet_id + RLS, n'importe quel tenant peut lire les vérifications d'un autre.
-- Réf. : issue #791 ; docs/05 §10.6 ; db/README §4.
--
-- Stratégie :
--   1. Ajouter cabinet_id (FK → cabinet, NOT NULL) dérivé de provider.cabinet_id.
--   2. ENABLE + FORCE ROW LEVEL SECURITY.
--   3. Policy tenant_isolation (fail-closed, même modèle que les autres tables tenant).
--   4. Mise à jour du seed : les lignes existantes héritent du cabinet_id du provider.

-- 1. Ajouter la colonne (nullable d'abord pour la back-fill).
ALTER TABLE provider_verification
    ADD COLUMN IF NOT EXISTS cabinet_id uuid REFERENCES cabinet(id);

-- 2. Back-fill depuis provider.cabinet_id (toutes les lignes existantes).
UPDATE provider_verification pv
SET cabinet_id = p.cabinet_id
FROM provider p
WHERE pv.provider_id = p.id;

-- 3. Rendre NOT NULL maintenant que la colonne est remplie.
ALTER TABLE provider_verification
    ALTER COLUMN cabinet_id SET NOT NULL;

-- 4. Index tenant-first (performant pour la policy + les requêtes API).
CREATE INDEX IF NOT EXISTS idx_provider_verification_cabinet
    ON provider_verification (cabinet_id, provider_id, status);

-- 5. Activer Row-Level Security.
ALTER TABLE provider_verification ENABLE ROW LEVEL SECURITY;
ALTER TABLE provider_verification FORCE ROW LEVEL SECURITY;

-- 6. Policy tenant_isolation (fail-closed via nullif).
CREATE POLICY tenant_isolation ON provider_verification
    FOR ALL
    USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);
