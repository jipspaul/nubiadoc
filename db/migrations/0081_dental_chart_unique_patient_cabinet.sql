-- 0080_dental_chart_unique_patient_cabinet.sql
-- Un seul odontogramme par (patient, cabinet) — requis par le PUT atomique
-- (UPSERT ON CONFLICT) de la route PUT /v1/cabinet/patients/:id/dental-chart.
-- Issue : #782

ALTER TABLE dental_chart
  ADD CONSTRAINT dental_chart_patient_cabinet_unique UNIQUE (patient_id, cabinet_id);
