-- 0225_ccam_act_catalog_extend.sql
-- Étend le référentiel `ccam_act` (0119) au-delà de l'extrait représentatif
-- initial (31 lignes) : ajout d'actes dentaires courants supplémentaires de
-- la nomenclature CCAM (source CNAM/ameli), pour rapprocher le catalogue
-- d'un référentiel complet. #4054.
--
-- Forward-only : 0119 est immuable, cette migration complète le catalogue
-- via le même mécanisme d'upsert (ON CONFLICT DO UPDATE).

INSERT INTO ccam_act (code, label, tarif_cents) VALUES
  ('HBMD002', 'Réparation d''une couronne ou d''un bridge en bouche',      2500),
  ('HBLD027', 'Reconstitution corono-radiculaire, incisive/canine',       6000),
  ('HBLD055', 'Ablation d''un inlay-core',                                 4000),
  ('HBGD473', 'Curetage sous-gingival, un sextant',                       3000),
  ('HBFD027', 'Freinectomie labiale ou linguale',                          8500),
  ('HBGD007', 'Gingivoplastie, un sextant',                                6500),
  ('HBFA015', 'Ostéotomie alvéolaire (crête édentée)',                    9500),
  ('HBLD005', 'Avulsion de dent temporaire',                               2000),
  ('HBLD030', 'Avulsion de dent définitive incluse (hors sagesse)',        7500),
  ('HBGA027', 'Alvéolectomie, un sextant',                                 6000),
  ('HBED013', 'Reprise de traitement endodontique, une racine',           5500),
  ('HBED029', 'Pulpotomie (dent temporaire)',                              2200),
  ('HBED042', 'Coiffage pulpaire direct',                                  1600),
  ('HBLD012', 'Apexification (obturation canalaire au calcium)',          4200),
  ('HBQD012', 'Radiographie occlusale',                                    1500),
  ('HBQK001', 'Bilan parodontal complet',                                  3500),
  ('HBQP002', 'Consultation de dépistage bucco-dentaire (MT dents)',       2300),
  ('HBLD449', 'Pose d''une prothèse amovible partielle, un à trois éléments', 25000),
  ('HBLD450', 'Pose d''une prothèse amovible complète, une arcade',        35000),
  ('HBLD451', 'Rebasage d''une prothèse amovible',                         8000),
  ('HBLD452', 'Réparation d''une prothèse amovible avec empreinte',        6000),
  ('HBMD481', 'Pose d''un inlay/onlay céramique ou composite',            15000),
  ('HBMD500', 'Pose d''une couronne provisoire',                           3000),
  ('HBBD010', 'Comblement d''alvéole post-extractionnelle',                7000),
  ('HBLD060', 'Élévation du plancher sinusien par voie latérale',        70000),
  ('HBQD028', 'Bilan radiographique long cône, six clichés',               4500),
  ('YYYY015', 'Anesthésie locale complémentaire',                          800),
  ('YYYY030', 'Sédation consciente au MEOPA, séance',                     6500),
  ('HBMD030', 'Dépose d''une couronne ou d''un bridge',                    3000),
  ('HBFD010', 'Traitement d''une péricoronarite',                          2500),
  ('HBGA045', 'Chirurgie parodontale régénératrice, un sextant',         15000)
ON CONFLICT (code) DO UPDATE SET
  label       = EXCLUDED.label,
  tarif_cents = EXCLUDED.tarif_cents,
  active      = true;
