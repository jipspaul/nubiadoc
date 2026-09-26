-- 0303_treatment_phase_description.sql
-- [rust-api] #7715 : `treatment_phase` n'avait aucune colonne pour la phrase
-- en langue claire que le praticien rédige pour traduire la nomenclature
-- d'une phase au patient (#5297 : le front (`PatientTreatmentPlanPhase.
-- description`, `_PhaseDescriptionText` côté `treatment_plan_detail_page.dart`)
-- lit `description` depuis toujours, mais l'API n'avait ni colonne ni champ
-- à exposer — la ligne ne s'affichait jamais, verbatim maquette
-- design-v2 (`Patient Mon plan de soins v2.html`).

ALTER TABLE treatment_phase
    ADD COLUMN description text;

COMMENT ON COLUMN treatment_phase.description IS
    'Phrase en langue claire (rédigée par le praticien) qui traduit la nomenclature de la phase pour le patient. Nullable : pas de valeur fabriquée si absente. #7715/#5297.';
