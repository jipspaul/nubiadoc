-- 0284_create_medication_reference.sql
-- Référentiel médicament (DCI, forme galénique, classe thérapeutique) pour
-- la recherche « Médicament (DCI) » de la composition d'ordonnance (#7433).
--
-- Root cause de #7433 : le champ de recherche front (#4987/#6104) existe et
-- appelle SearchMedicationReferencesUseCase, mais aucune source de données
-- n'a jamais été câblée — ni table, ni endpoint, ni repository. En dehors
-- des 19 modèles pré-remplis, un praticien ne pouvait poser aucun
-- médicament.
--
-- Table publique en lecture (pas de RLS, comme ccam_act, migration 0119) :
-- le référentiel médicament est national, aucune donnée patient.

CREATE TABLE IF NOT EXISTS medication_reference (
    id                 UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    dci                TEXT    NOT NULL,
    galenic_form       TEXT    NOT NULL,
    therapeutic_class  TEXT    NOT NULL,
    active             BOOLEAN NOT NULL DEFAULT true
);

COMMENT ON TABLE medication_reference IS
    'Référentiel médicament (DCI, forme galénique, classe thérapeutique). Public en lecture, non tenant. #7433.';

-- Recherche insensible à la casse ET aux accents (même pattern que
-- ccam_act_label_norm_idx, migration 0119).
CREATE INDEX IF NOT EXISTS medication_reference_dci_norm_idx
    ON medication_reference (translate(lower(dci),
        'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn'));

GRANT SELECT ON medication_reference TO nubia_app;

-- ── Référentiel (extrait représentatif des médicaments courants en cabinet
--    dentaire : antibioprophylaxie, antalgiques, antiseptiques) ────────────
INSERT INTO medication_reference (dci, galenic_form, therapeutic_class) VALUES
  ('Amoxicilline 1 g',                          'comprimé dispersible',        'Pénicilline'),
  ('Amoxicilline 500 mg',                       'gélule',                      'Pénicilline'),
  ('Amoxicilline 2 g',                          'comprimé dispersible',        'Pénicilline'),
  ('Amoxicilline/Acide clavulanique 1 g/125 mg','comprimé',                    'Pénicilline'),
  ('Clindamycine 600 mg',                       'comprimé',                    'Lincosamide'),
  ('Clindamycine 300 mg',                       'gélule',                      'Lincosamide'),
  ('Spiramycine 3 M UI',                        'comprimé',                    'Macrolide'),
  ('Azithromycine 250 mg',                      'comprimé',                    'Macrolide'),
  ('Métronidazole 500 mg',                      'comprimé',                    'Imidazolé'),
  ('Paracétamol 1 g',                           'comprimé',                    'Antalgique non opioïde'),
  ('Paracétamol 500 mg',                        'gélule',                      'Antalgique non opioïde'),
  ('Ibuprofène 400 mg',                         'comprimé',                    'Anti-inflammatoire non stéroïdien'),
  ('Ibuprofène 200 mg',                         'comprimé',                    'Anti-inflammatoire non stéroïdien'),
  ('Tramadol 50 mg',                            'gélule',                      'Antalgique opioïde faible'),
  ('Codéine/Paracétamol 20 mg/500 mg',          'comprimé',                    'Antalgique opioïde faible'),
  ('Prednisolone 20 mg',                        'comprimé',                    'Corticoïde'),
  ('Chlorhexidine 0,12 %',                      'solution pour bain de bouche','Antiseptique'),
  ('Chlorhexidine 0,2 %',                       'solution pour bain de bouche','Antiseptique'),
  ('Lidocaïne 2 %',                             'solution injectable',         'Anesthésique local'),
  ('Articaïne/Adrénaline 40 mg/0,005 mg',       'solution injectable',         'Anesthésique local');
