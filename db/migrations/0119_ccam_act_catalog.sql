-- 0119_ccam_act_catalog.sql
-- Référentiel CCAM des actes dentaires (catalogue de référence, non tenant).
-- Utilisé par le picker CCAM de la consultation praticien (#3226) : le
-- praticien recherche un acte par code ou libellé pour l'ajouter à la séance.
--
-- Table publique en lecture (pas de RLS, comme medical_act) : le catalogue
-- CCAM est un référentiel national, aucune donnée patient. `tarif_cents` =
-- base de remboursement indicative (aide à la saisie ; le montant réel de
-- l'acte reste saisi par le praticien dans consultation_act.amount_cents).

CREATE TABLE IF NOT EXISTS ccam_act (
    code        text PRIMARY KEY,
    label       text NOT NULL,
    tarif_cents integer,
    active      boolean NOT NULL DEFAULT true
);

COMMENT ON TABLE ccam_act IS
    'Référentiel CCAM (actes dentaires). Public en lecture, non tenant. #3226.';
COMMENT ON COLUMN ccam_act.tarif_cents IS
    'Base de remboursement indicative en centimes (saisie assistée).';

-- Recherche insensible à la casse ET aux accents (les praticiens tapent
-- souvent sans accents) : index sur le libellé normalisé.
CREATE INDEX IF NOT EXISTS ccam_act_label_norm_idx
    ON ccam_act (translate(lower(label),
        'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn'));

GRANT SELECT ON ccam_act TO nubia_app;

-- ── Catalogue (extrait représentatif des actes dentaires courants) ──────────
INSERT INTO ccam_act (code, label, tarif_cents) VALUES
  ('HBQK002', 'Examen bucco-dentaire (bilan)',                             2300),
  ('HBGD036', 'Détartrage sus- et sous-gingival, deux arcades',           2864),
  ('HBGD017', 'Détartrage complémentaire',                                1500),
  ('HBFD001', 'Surfaçage radiculaire, un sextant',                        8000),
  ('HBJD001', 'Obturation d''une dent, une face (composite)',             1907),
  ('HBJD002', 'Obturation d''une dent, deux faces (composite)',           3325),
  ('HBJD003', 'Obturation d''une dent, trois faces ou plus (composite)',  4529),
  ('HBFD003', 'Scellement prophylactique de sillon, une dent',            1300),
  ('HBFD004', 'Application de fluorure, séance',                          2500),
  ('HBGD432', 'Désensibilisation dentinaire',                            1800),
  ('HBBD001', 'Pose d''un inlay-core',                                    9000),
  ('HBLD724', 'Avulsion d''une dent permanente sur arcade',              3348),
  ('HBGD047', 'Avulsion de dent de sagesse incluse',                    10000),
  ('HBED001', 'Traitement endodontique d''une incisive/canine',          3381),
  ('HBED002', 'Traitement endodontique d''une prémolaire',               4831),
  ('HBED003', 'Traitement endodontique d''une molaire',                  8118),
  ('HBLD036', 'Reconstitution corono-radiculaire (tenon)',               7500),
  ('HBMD490', 'Pose d''une couronne dentaire prothétique',              12000),
  ('HBLD038', 'Pose d''un bridge (trois éléments)',                     28000),
  ('HBLD467', 'Réparation d''une prothèse dentaire',                     5000),
  ('HBQD001', 'Radiographie rétro-alvéolaire',                           1550),
  ('HBQD003', 'Radiographie panoramique dentaire',                       2109),
  ('LBQK001', 'Radiographie type téléradiographie du crâne',             2500),
  ('HBLD001', 'Pose d''un implant dentaire',                            60000),
  ('HBMD001', 'Pilier implantaire et couronne sur implant',             90000),
  ('HBBD002', 'Greffe osseuse pré-implantaire',                         50000),
  ('HBFD002', 'Gingivectomie, un sextant',                              6000),
  ('HBPD001', 'Traitement d''une urgence : soulagement de la douleur',    3000),
  ('HBHD001', 'Blanchiment dentaire (hors nomenclature)',               25000),
  ('HBMD002', 'Pose de facette céramique',                              45000),
  ('HBLD745', 'Contention parodontale',                                 12000),
  ('TRAUMA1', 'Réimplantation d''une dent luxée',                       15000)
ON CONFLICT (code) DO UPDATE SET
  label       = EXCLUDED.label,
  tarif_cents = EXCLUDED.tarif_cents,
  active      = true;
