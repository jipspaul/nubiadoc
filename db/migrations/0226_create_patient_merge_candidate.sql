-- 0226_create_patient_merge_candidate.sql
-- Table patient_merge_candidate (#3916, lot interop A5) : détection de
-- doublons patient au sein d'un même cabinet, avec résolution humaine
-- (pas de fusion automatique en v1 — la fusion réelle existe déjà,
-- fonction merge_patient(), migration 0178/#4101, exposée en API par
-- patient_merge.rs/#4102).
--
-- Portée volontairement réduite par rapport au corps de l'issue (qui parle
-- de comparaison INS déchiffré) : la lecture/recherche patient par INS
-- (lot A4, #3915) reste bloquée en amont (le câblage applicatif de
-- core-crypto sur les colonnes patient.ins_ciphertext/patient_account.
-- ins_ciphertext n'existe nulle part dans api/src à ce jour — aucun
-- appelant de encrypt_column/decrypt_column, aucune écriture de
-- patient.ins_ciphertext). Comparer des ciphertexts AES-256-GCM en SQL est
-- impossible (nonce aléatoire par valeur, cf. core-crypto/src/lib.rs) et
-- décrypter côté API à chaque écriture pour comparer tout le cabinet est un
-- chantier séparé qui dépend de #3915.
--
-- Flagging retenu ici (sans dépendre du déchiffrement INS) :
--   - même `ins_bidx` (index aveugle : HMAC-SHA256 de l'INS en clair,
--     calculé côté API AVANT chiffrement, colonne ajoutée sur `patient` par
--     cette migration) sur 2 patients actifs du même cabinet ;
--   - repli défini par l'issue : même `ins_bidx` MAIS démographie
--     divergente (nom/prénom/naissance différents) — flag avec severity
--     'ins_and_demographics_diverge' plutôt que 'same_ins', pour laisser au
--     secrétariat un signal explicite qu'il ne s'agit peut-être PAS d'un
--     doublon franc (erreur de saisie INS possible).
-- `ins_bidx` est NULL tant qu'aucun call site ne le renseigne (câblage API
-- hors scope ici, comme le chiffrement lui-même) — le trigger ne flague
-- donc rien tant que #3915 n'est pas livré, mais l'infrastructure (table,
-- RLS, index, endpoint de résolution) est prête à recevoir les écritures
-- dès que la colonne sera alimentée, sans nouvelle migration.
--
-- Endpoint cabinet de résolution humaine : GET (liste) + POST .../resolve
-- (marque `resolved`, sans fusion auto — l'admin choisit ensuite d'appeler
-- POST /v1/cabinet/patients/:id/merge, #4102, s'il juge que c'est un vrai
-- doublon) — cf. api/src/patient_merge_candidate.rs.

-- Index aveugle HMAC-SHA256(INS clair) — déterministe (même INS -> même
-- valeur), mais non réversible (contrairement à ins_ciphertext, qui est
-- chiffré par enveloppe avec un nonce aléatoire, donc jamais comparable en
-- SQL). Calculé et renseigné côté API au moment où l'INS est saisi/déchiffré
-- (hors scope de cette migration, dépend de #3915) — colonne pré-créée pour
-- ne pas bloquer ce lot sur l'ordre de livraison.
ALTER TABLE patient ADD COLUMN ins_bidx text;

COMMENT ON COLUMN patient.ins_bidx IS
    'Index aveugle HMAC-SHA256(INS en clair, clé app INS_BIDX_KEY) — permet de comparer deux INS sans les déchiffrer. NULL tant que non renseigné par le call site de saisie INS (#3915). #3916.';

CREATE INDEX idx_patient_ins_bidx ON patient (cabinet_id, ins_bidx) WHERE ins_bidx IS NOT NULL;

CREATE TABLE patient_merge_candidate (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id        uuid        NOT NULL REFERENCES cabinet(id),
    patient_a_id      uuid        NOT NULL,
    patient_b_id      uuid        NOT NULL,
    reason            text        NOT NULL
                          CHECK (reason IN ('same_ins', 'ins_and_demographics_diverge')),
    status            text        NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending', 'resolved', 'dismissed')),
    resolved_by        uuid        REFERENCES app_user(id),
    resolved_at        timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    -- ordre canonique (a < b) pour que l'UNIQUE ci-dessous empêche un doublon
    -- de flag pour la même paire, quel que soit l'ordre de détection.
    CONSTRAINT patient_merge_candidate_ordered_pair CHECK (patient_a_id < patient_b_id),
    CONSTRAINT patient_merge_candidate_resolution_pair
        CHECK ((status = 'pending') = (resolved_by IS NULL AND resolved_at IS NULL)),
    UNIQUE (cabinet_id, patient_a_id, patient_b_id)
);

-- FK composites (patient_id, cabinet_id) plutôt que FK simple sur l'id seul :
-- même garde que le reste du schéma (cf. migration 0193/0212) — les
-- vérifications FK bypassent la RLS, un FK simple laisserait un cabinet B
-- flaguer une paire incluant un patient du cabinet A.
ALTER TABLE patient_merge_candidate
    ADD CONSTRAINT patient_merge_candidate_a_cabinet_fkey
    FOREIGN KEY (patient_a_id, cabinet_id) REFERENCES patient (id, cabinet_id);
ALTER TABLE patient_merge_candidate
    ADD CONSTRAINT patient_merge_candidate_b_cabinet_fkey
    FOREIGN KEY (patient_b_id, cabinet_id) REFERENCES patient (id, cabinet_id);

CREATE INDEX idx_patient_merge_candidate_cabinet_status
    ON patient_merge_candidate (cabinet_id, status);

COMMENT ON TABLE patient_merge_candidate IS
    'Doublons patient flagués automatiquement (même INS, ou même INS + démographie divergente) au sein d''un cabinet — résolution humaine uniquement (pas de fusion auto en v1). #3916.';

GRANT SELECT, INSERT, UPDATE, DELETE ON patient_merge_candidate TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON patient_merge_candidate TO nubia_seed;

ALTER TABLE patient_merge_candidate ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient_merge_candidate FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON patient_merge_candidate
    FOR ALL
    USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- ---------------------------------------------------------------------------
-- Flagging automatique : trigger sur patient (INSERT/UPDATE de ins_bidx).
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER + row_security=off (même pattern que merge_patient,
-- 0178) : le trigger doit pouvoir lire d'autres lignes `patient` du même
-- cabinet indépendamment de la session RLS courante, et écrire dans
-- patient_merge_candidate même si la session appelante n'a pas explicitement
-- posé app.current_cabinet_id (ex. import batch) — le filtre cabinet reste
-- strictement NEW.cabinet_id, jamais cross-tenant.
CREATE OR REPLACE FUNCTION flag_patient_merge_candidates()
RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET row_security = off
    SET search_path = public
AS $$
DECLARE
    r RECORD;
    v_reason text;
    v_a uuid;
    v_b uuid;
BEGIN
    IF NEW.ins_bidx IS NULL OR NEW.deleted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    FOR r IN
        SELECT id, first_name, last_name, birth_date
        FROM patient
        WHERE cabinet_id = NEW.cabinet_id
          AND id <> NEW.id
          AND deleted_at IS NULL
          AND ins_bidx = NEW.ins_bidx
    LOOP
        IF r.first_name IS DISTINCT FROM NEW.first_name
           OR r.last_name IS DISTINCT FROM NEW.last_name
           OR r.birth_date IS DISTINCT FROM NEW.birth_date THEN
            v_reason := 'ins_and_demographics_diverge';
        ELSE
            v_reason := 'same_ins';
        END IF;

        -- ordre canonique de la paire (contrainte patient_a_id < patient_b_id).
        IF NEW.id < r.id THEN
            v_a := NEW.id;
            v_b := r.id;
        ELSE
            v_a := r.id;
            v_b := NEW.id;
        END IF;

        INSERT INTO patient_merge_candidate (cabinet_id, patient_a_id, patient_b_id, reason)
        VALUES (NEW.cabinet_id, v_a, v_b, v_reason)
        ON CONFLICT (cabinet_id, patient_a_id, patient_b_id)
        DO UPDATE SET reason = EXCLUDED.reason
            WHERE patient_merge_candidate.status = 'pending';
    END LOOP;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION flag_patient_merge_candidates() IS
    'Trigger patient AFTER INSERT/UPDATE : flague automatiquement dans patient_merge_candidate tout autre patient actif du même cabinet partageant le même ins_bidx (même INS, ou même INS + démographie divergente). #3916.';

CREATE TRIGGER patient_flag_merge_candidates
    AFTER INSERT OR UPDATE OF ins_bidx, first_name, last_name, birth_date ON patient
    FOR EACH ROW
    WHEN (NEW.ins_bidx IS NOT NULL)
    EXECUTE FUNCTION flag_patient_merge_candidates();
