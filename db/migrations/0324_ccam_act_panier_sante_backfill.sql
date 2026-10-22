-- 0324_ccam_act_panier_sante_backfill.sql
-- `ccam_act.panier_sante` (0161, #4055) est resté NULL sur les 62 lignes du
-- catalogue depuis sa création : la classification officielle CNAM
-- 100% Santé n'avait jamais été saisie. Conséquence (#6767) : le bandeau
-- réglementaire « alternative reste à charge zéro » (#4061) ne peut
-- s'afficher pour aucun patient, puisque `panierSante` vaut toujours `null`
-- côté front (front/API déjà corrects, cf. #6767).
--
-- Cette migration ne classe QUE les actes réellement concernés par le
-- panier 100% Santé : les actes prothétiques (`category = 'prothese'`,
-- couronnes/bridges/inlay-cores — 0283) et l'endodontie
-- (`category = 'endo'`), conformément à la nomenclature 100% Santé
-- dentaire. Les autres catégories (soins conservateurs, parodontologie,
-- chirurgie, implantologie, imagerie...) restent NULL à dessein : elles ne
-- relèvent pas d'un panier RAC0/modéré/libre, et 0161 avertit explicitement
-- de ne jamais déduire `rac0` d'une valeur NULL — donc NULL demeure correct
-- pour ces actes, pas un trou de données.

-- ── Prothèse fixe ────────────────────────────────────────────────────────
UPDATE ccam_act SET panier_sante = 'modere'
  WHERE code IN ('HBBD001', 'HBLD036', 'HBLD038', 'HBLD027');

UPDATE ccam_act SET panier_sante = 'rac0'
  WHERE code IN ('HBMD490');

UPDATE ccam_act SET panier_sante = 'libre'
  WHERE code IN ('HBLD467', 'HBMD002', 'HBMD481');

UPDATE ccam_act SET panier_sante = 'hors_nomenclature'
  WHERE code IN ('HBLD055', 'HBMD500', 'HBMD030');

-- ── Endodontie ───────────────────────────────────────────────────────────
UPDATE ccam_act SET panier_sante = 'rac0'
  WHERE code IN ('HBED001', 'HBED002', 'HBED029', 'HBED042');

UPDATE ccam_act SET panier_sante = 'modere'
  WHERE code IN ('HBED003', 'HBED013', 'HBLD012');
