-- 0183_create_ccam_act_incompatibility.sql
-- Règles de cumul d'actes interdits (#4116) : aucune règle d'association
-- n'est vérifiée (ex. deux actes non cumulables le même jour sur la même
-- dent), pourtant standard conventionnel (règles de non-cumul NGAP/CCAM).
--
-- Référentiel catalogue (comme ccam_act/ccam_act_bundle, migrations 0119 et
-- 0182) : public en lecture, non tenant, aucune donnée patient — même choix
-- RLS (aucune).
--
-- code_a < code_b (CHECK, ordre lexicographique du texte) : une paire est
-- symétrique ("A incompatible avec B" = "B incompatible avec A"), la
-- contrainte canonise l'ordre de stockage pour qu'une paire n'existe jamais
-- deux fois sous deux orientations contradictoires. La requête applicative
-- devra donc tester (code_a, code_b) dans les deux sens (LEAST/GREATEST des
-- deux codes saisis), pas juste une égalité directe.
--
-- Pas de données de seed : les paires réellement non cumulables (quels
-- codes CCAM, pour quel motif réglementaire) sont une donnée métier précise
-- non fournie par l'issue — l'inventer serait fabriquer une règle de
-- facturation. Structure seule ; remplissage laissé à une décision humaine
-- (praticien/expert métier, référentiel NGAP/CCAM officiel).

CREATE TABLE ccam_act_incompatibility (
    id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code_a text NOT NULL REFERENCES ccam_act(code),
    code_b text NOT NULL REFERENCES ccam_act(code),
    reason text NOT NULL,
    CHECK (code_a < code_b),
    UNIQUE (code_a, code_b)
);

CREATE INDEX idx_ccam_act_incompatibility_code_b
    ON ccam_act_incompatibility (code_b);

GRANT SELECT ON ccam_act_incompatibility TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ccam_act_incompatibility TO nubia_seed;

COMMENT ON TABLE ccam_act_incompatibility IS
    'Paires de codes CCAM non cumulables (règles de non-cumul conventionnelles). code_a < code_b (paire canonisée, symétrique). Référentiel public en lecture, non tenant. #4116.';
