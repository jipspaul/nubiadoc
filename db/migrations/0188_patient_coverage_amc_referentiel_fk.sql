-- 0188_patient_coverage_amc_referentiel_fk.sql
-- FK optionnelle de patient_coverage vers mutuelle_referentiel (#4127),
-- migration 0187. Le champ texte libre `amc` (migration 0023) est CONSERVÉ
-- en repli : aucune migration automatique du texte existant vers la FK
-- n'est effectuée ici — un rapprochement texte-libre → référentiel par nom
-- serait un matching approximatif (fautes de frappe, abréviations,
-- raisons sociales différentes) risquant de lier une couverture patient au
-- mauvais organisme. `amc_referentiel_id` reste NULL tant que le
-- rapprochement n'est pas fait explicitement (par le patient/cabinet, ou
-- un script de reconciliation dédié hors scope de cette migration).

ALTER TABLE patient_coverage
    ADD COLUMN amc_referentiel_id uuid REFERENCES mutuelle_referentiel(id);

CREATE INDEX idx_patient_coverage_amc_referentiel
    ON patient_coverage (amc_referentiel_id)
    WHERE amc_referentiel_id IS NOT NULL;

COMMENT ON COLUMN patient_coverage.amc_referentiel_id IS
    'FK optionnelle vers mutuelle_referentiel(id). NULL si l''organisme n''est pas dans le référentiel (ou pas encore rapproché) : amc (texte libre) reste alors la seule source. #4127.';
