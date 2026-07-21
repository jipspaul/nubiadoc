-- 0174_patient_coverage_periode.sql
-- Période de validité des droits mutuelle (#4096) : `patient_coverage`
-- (migration 0023) ne traçait aucune période — deux colonnes date
-- nullables, sans impact sur la RLS patient-scoped existante
-- (patient_coverage_owner, GUC app.patient_account_id).

ALTER TABLE patient_coverage
    ADD COLUMN periode_debut date,
    ADD COLUMN periode_fin date;

ALTER TABLE patient_coverage
    ADD CONSTRAINT patient_coverage_periode_order_chk
        CHECK (
            periode_debut IS NULL OR periode_fin IS NULL
            OR periode_fin > periode_debut
        );

COMMENT ON COLUMN patient_coverage.periode_debut IS 'Début de validité des droits mutuelle — nullable, informatif. Issue #4096.';
COMMENT ON COLUMN patient_coverage.periode_fin IS 'Fin de validité des droits mutuelle — nullable ; si renseignée avec periode_debut, doit lui être strictement postérieure.';
