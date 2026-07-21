-- 0159_ngap_act_catalog.sql
-- Référentiel NGAP des actes dentaires (catalogue de référence, non tenant).
-- Le catalogue ccam_act (migration 0119) ne couvre que la CCAM ; le
-- référentiel dentaire complet exige CCAM+NGAP maintenus à jour (§4.1, un
-- des 5 piliers du noyau de survie) — cette table couvre le volet NGAP.
--
-- Même pattern que ccam_act : table publique en lecture (pas de RLS), aucune
-- donnée patient. `lettre_cle`/`coefficient` sont la décomposition NGAP
-- (ex. SC13 = lettre-clé SC, coefficient 13) ; `tarif_cents` est la valeur
-- calculée correspondante, dénormalisée pour éviter un calcul lettre-clé →
-- tarif côté application (les valeurs de lettre-clé changent par arrêté).

CREATE TABLE IF NOT EXISTS ngap_act (
    code        text PRIMARY KEY,
    lettre_cle  text NOT NULL,
    coefficient numeric(6, 2) NOT NULL,
    label       text NOT NULL,
    tarif_cents integer,
    active      boolean NOT NULL DEFAULT true
);

COMMENT ON TABLE ngap_act IS
    'Référentiel NGAP (actes dentaires). Public en lecture, non tenant. #4052.';
COMMENT ON COLUMN ngap_act.lettre_cle IS
    'Lettre-clé NGAP (ex. SC, DC, SPR, ORT) — décomposition du code.';
COMMENT ON COLUMN ngap_act.coefficient IS
    'Coefficient appliqué à la lettre-clé pour obtenir le tarif conventionnel.';
COMMENT ON COLUMN ngap_act.tarif_cents IS
    'Tarif conventionnel en centimes, dénormalisé (lettre_cle × coefficient).';

-- Recherche insensible à la casse ET aux accents, même index que ccam_act.
CREATE INDEX IF NOT EXISTS ngap_act_label_norm_idx
    ON ngap_act (translate(lower(label),
        'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn'));

GRANT SELECT ON ngap_act TO nubia_app;

-- ── Catalogue (extrait représentatif des actes dentaires courants) ──────────
INSERT INTO ngap_act (code, lettre_cle, coefficient, label, tarif_cents) VALUES
  ('DC',     'DC',  1,     'Consultation par un chirurgien-dentiste',            2300),
  ('SC13',   'SC',  13,    'Soins conservateurs, une face (obturation)',         1907),
  ('SC17',   'SC',  17,    'Soins conservateurs, deux faces (obturation)',       2494),
  ('SC22',   'SC',  22,    'Soins conservateurs, trois faces ou plus',           3229),
  ('SC10',   'SC',  10,    'Traitement d''une pulpite (biopulpectomie), incisive', 1468),
  ('SC15',   'SC',  15,    'Traitement d''une pulpite, prémolaire',               2202),
  ('SC25',   'SC',  25,    'Traitement d''une pulpite, molaire',                  3670),
  ('DTS7',   'D',   7,     'Détartrage, deux séances maximum par an',            1028),
  ('SPR50',  'SPR', 50,    'Couronne dentaire prothétique, base conventionnelle', 10750),
  ('SPR60',  'SPR', 60,    'Bridge, élément intermédiaire',                      12900),
  ('SPR30',  'SPR', 30,    'Prothèse amovible partielle, base',                   6450),
  ('ORT90',  'ORT', 90,    'Traitement orthodontique, semestre',                 19350),
  ('IK',     'IK',  1,     'Indemnité kilométrique, déplacement praticien',        150),
  ('TO',     'TO',  1,     'Radiographie intra-buccale rétro-alvéolaire',         1550),
  ('Z7',     'Z',   7,     'Radiographie panoramique dentaire',                   2109)
ON CONFLICT (code) DO UPDATE SET
  lettre_cle  = EXCLUDED.lettre_cle,
  coefficient = EXCLUDED.coefficient,
  label       = EXCLUDED.label,
  tarif_cents = EXCLUDED.tarif_cents,
  active      = true;
