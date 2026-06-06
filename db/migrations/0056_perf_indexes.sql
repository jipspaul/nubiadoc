-- 0056_perf_indexes.sql
-- Index performance : patient_account.contact (JSONB GIN) + appointment date range.
-- Issue : #854. Réf. : docs/12-api-reference.md §6-7, db/README §8.
--
-- 1. GIN sur patient_account.contact (jsonb_path_ops) — recherche JSONB rapide
--    (email, tel) sans seq-scan sur la table plateforme.
-- 2. Index composé appointment(cabinet_id, starts_at DESC) — tri/filtre agenda
--    sur un cabinet (requête fréquente GET /v1/appointments).
-- 3. Index appointment(patient_id, starts_at DESC) — dashboard patient
--    (policy appointment_patient_read : patient_id IN (SELECT id FROM patient
--     WHERE patient_account_id = ?)), évite seq-scan + sort.

CREATE INDEX IF NOT EXISTS idx_patient_account_contact
    ON patient_account USING gin (contact jsonb_path_ops);

CREATE INDEX IF NOT EXISTS idx_appointment_cabinet_starts_at
    ON appointment (cabinet_id, starts_at DESC);

CREATE INDEX IF NOT EXISTS idx_appointment_patient_starts_at
    ON appointment (patient_id, starts_at DESC);
