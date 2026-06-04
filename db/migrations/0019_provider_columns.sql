-- 0019_provider_columns.sql
-- Complète la table provider : user_id (lien direct app_user), specialite (text),
-- created_at, NOT NULL sur cabinet_id. Index (is_listed, rpps_verified) pour
-- le filtre annuaire chaud. Réf. : docs/05 §9.3, docs/07 §4.7. Issue : #208.

-- Lien direct au compte utilisateur propriétaire du profil.
ALTER TABLE provider ADD COLUMN IF NOT EXISTS user_id    uuid REFERENCES app_user(id);
ALTER TABLE provider ALTER COLUMN user_id SET NOT NULL;

-- Spécialité en texte libre (complète specialty_id qui reste pour l'annuaire structuré).
ALTER TABLE provider ADD COLUMN IF NOT EXISTS specialite text;

-- Horodatage de création (absent de la définition initiale 0009).
ALTER TABLE provider ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- cabinet_id doit être non nul (praticien toujours rattaché à un cabinet).
ALTER TABLE provider ALTER COLUMN cabinet_id SET NOT NULL;

-- Index composite pour le filtre annuaire : is_listed ET rpps_verified filtrés ensemble.
CREATE INDEX IF NOT EXISTS provider_listed_rpps_verified_idx
    ON provider (is_listed, rpps_verified);
