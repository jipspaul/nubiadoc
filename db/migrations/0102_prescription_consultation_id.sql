-- 0102_prescription_consultation_id.sql
-- Ajoute consultation_id optionnel sur prescription.
-- L'ordonnance peut être liée à une séance de consultation (nullable :
-- une ordonnance peut être créée hors consultation).
-- Issue : #2038

ALTER TABLE prescription
    ADD COLUMN IF NOT EXISTS consultation_id uuid REFERENCES consultation_session(id);
