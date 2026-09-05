-- 0258_patient_merge_candidate.sql
-- Lot A5 (#3916) : détection de doublons du référentiel patient.
--
-- 1. `patient.ins_hash` : empreinte DÉTERMINISTE de l'INS (SHA-256 salée par
--    la clé maître KMS, calculée côté application — db/README §5 : aucun
--    chiffrement/hachage de donnée de santé en SQL). L'INS chiffré par
--    enveloppe (ins_ciphertext) est non déterministe par construction : il
--    est invérifiable en SQL, donc inutilisable pour détecter « même INS sur
--    2 patients ». Le hash comble ce trou sans exposer l'INS (préimage
--    protégée par le sel serveur). Renseigné par le chemin ADT (B8) au fil
--    de l'eau ; les lignes historiques restent NULL (pas de backfill
--    possible en SQL, le déchiffrement est applicatif).
-- 2. `patient_merge_candidate` : paires de patients d'un même cabinet
--    partageant un INS, à résoudre par un HUMAIN (aucune fusion automatique
--    en v1 — la fusion se fait via POST /v1/cabinet/patients/:id/merge,
--    fonction merge_patient() de 0178).

ALTER TABLE patient ADD COLUMN ins_hash text;
CREATE INDEX idx_patient_cabinet_ins_hash
    ON patient (cabinet_id, ins_hash) WHERE ins_hash IS NOT NULL;

CREATE TABLE patient_merge_candidate (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id   uuid        NOT NULL REFERENCES cabinet(id),
    -- Paire ordonnée (patient_a < patient_b, garde CHECK) : une seule ligne
    -- par paire quel que soit l'ordre de détection.
    patient_a    uuid        NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    patient_b    uuid        NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    reason       text        NOT NULL
                             CHECK (reason IN ('same_ins', 'same_ins_demographie_divergente')),
    status       text        NOT NULL DEFAULT 'open'
                             CHECK (status IN ('open', 'dismissed')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT patient_merge_candidate_ordered CHECK (patient_a < patient_b),
    CONSTRAINT patient_merge_candidate_pair UNIQUE (cabinet_id, patient_a, patient_b)
);

ALTER TABLE patient_merge_candidate ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_merge_candidate FORCE ROW LEVEL SECURITY;

CREATE POLICY patient_merge_candidate_cabinet_isolation ON patient_merge_candidate
    FOR ALL
    TO nubia_app
    USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON patient_merge_candidate TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON patient_merge_candidate TO nubia_seed;
