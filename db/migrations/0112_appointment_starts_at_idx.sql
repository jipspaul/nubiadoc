-- 0112_appointment_starts_at_idx.sql
-- Index appointment(cabinet_id, starts_at) et (patient_id, starts_at) pour les
-- requêtes de liste RDV triés par date ; index partiel sur les RDV confirmés
-- pour l'affichage dashboard patient.
-- Issue : #2472 (contexte)

CREATE INDEX IF NOT EXISTS idx_appointment_cabinet_starts_at
    ON appointment (cabinet_id, starts_at DESC);

CREATE INDEX IF NOT EXISTS idx_appointment_patient_starts_at
    ON appointment (patient_id, starts_at DESC);

CREATE INDEX IF NOT EXISTS idx_appointment_starts_at_confirmed
    ON appointment (starts_at)
    WHERE status = 'confirmed';
