-- 0163_provider_unavailability_substitute.sql
-- provider_unavailability (0116) couvre les congés/blocages mais ne permet
-- pas de renseigner qui remplace un praticien absent (#4158). Ajoute une
-- colonne nullable référençant provider(id).
--
-- ON DELETE SET NULL (pas CASCADE comme provider_id) : le remplaçant est une
-- information secondaire — si sa fiche provider est supprimée, l'indisponibilité
-- du praticien absent doit rester (seule la référence au remplaçant disparaît),
-- contrairement à provider_id dont la suppression fait disparaître
-- l'indisponibilité elle-même (c'est SA période bloquée).
--
-- RLS inchangée : provider_unavailability_cabinet_isolation (migration 0116)
-- ne référence que provider_id, pas cette nouvelle colonne — un
-- substitute_practitioner_id d'un autre cabinet resterait acceptable en base
-- (pas de contrainte cross-cabinet), mais l'API doit valider l'appartenance
-- au même cabinet côté application quand cette colonne sera exposée en
-- écriture (hors scope ici — schéma uniquement, cf. #4158 : aucun endpoint
-- provider_unavailability n'existe encore côté API).

ALTER TABLE provider_unavailability
    ADD COLUMN IF NOT EXISTS substitute_practitioner_id uuid REFERENCES provider(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_provider_unavailability_substitute
    ON provider_unavailability (substitute_practitioner_id)
    WHERE substitute_practitioner_id IS NOT NULL;

COMMENT ON COLUMN provider_unavailability.substitute_practitioner_id IS
    'Praticien remplaçant pendant cette période d''indisponibilité (#4158). '
    'NULL si aucun remplaçant désigné.';
