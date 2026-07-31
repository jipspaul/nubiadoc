-- 0212_patient_children_composite_fk.sql
-- #4291 : groupe "patient" de l'inventaire systémique — 19 tables enfants
-- référençaient patient(id) via une FK patient_id SIMPLE (patient a déjà
-- UNIQUE(id, cabinet_id), migration 0193). PostgreSQL fait bypasser la RLS
-- aux vérifications FK/UNIQUE/PK : une session du cabinet B pouvait
-- rattacher sa ligne à un patient du cabinet A, invisible en SELECT sous ce
-- même GUC. Même pattern que tous les fix précédents de cette série (0190,
-- 0198, 0200, 0210, 0211).
--
-- L'entrée "consent_record" listée dans l'audit d'origine est stale :
-- consent_record n'a plus de colonne patient_id depuis le refactor 0017
-- (devenue plateforme app_user_id/patient_account_id) — retirée de cette
-- migration, aucune action nécessaire.
--
-- document.patient_id est nullable (contrairement aux 18 autres, NOT NULL) :
-- la conversion composite (MATCH SIMPLE, défaut Postgres) n'exige la
-- correspondance que lorsque patient_id ET cabinet_id sont tous deux
-- renseignés — un document plateforme (cabinet_id NULL, carte mutuelle...)
-- n'a jamais patient_id renseigné en pratique (lié à patient_account_id),
-- donc aucune ligne existante ne peut casser.
--
-- Toutes les lignes existantes ont été insérées via une session déjà scopée
-- à un cabinet cohérent (RLS write, WITH CHECK cabinet_id) — la conversion
-- ne peut casser aucune ligne existante ; si une incohérence existait
-- malgré tout, cette migration échouerait explicitement au lieu de la
-- laisser passer silencieusement.

ALTER TABLE medical_record
    DROP CONSTRAINT medical_record_patient_id_fkey;
ALTER TABLE medical_record
    ADD CONSTRAINT medical_record_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE clinical_note
    DROP CONSTRAINT clinical_note_patient_id_fkey;
ALTER TABLE clinical_note
    ADD CONSTRAINT clinical_note_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE dental_chart
    DROP CONSTRAINT dental_chart_patient_id_fkey;
ALTER TABLE dental_chart
    ADD CONSTRAINT dental_chart_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE document
    DROP CONSTRAINT document_patient_id_fkey;
ALTER TABLE document
    ADD CONSTRAINT document_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE appointment
    DROP CONSTRAINT appointment_patient_id_fkey;
ALTER TABLE appointment
    ADD CONSTRAINT appointment_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE waiting_list_entry
    DROP CONSTRAINT waiting_list_entry_patient_id_fkey;
ALTER TABLE waiting_list_entry
    ADD CONSTRAINT waiting_list_entry_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE quote
    DROP CONSTRAINT quote_patient_id_fkey;
ALTER TABLE quote
    ADD CONSTRAINT quote_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE payment_schedule
    DROP CONSTRAINT payment_schedule_patient_id_fkey;
ALTER TABLE payment_schedule
    ADD CONSTRAINT payment_schedule_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE payment
    DROP CONSTRAINT payment_patient_id_fkey;
ALTER TABLE payment
    ADD CONSTRAINT payment_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE conversation
    DROP CONSTRAINT conversation_patient_id_fkey;
ALTER TABLE conversation
    ADD CONSTRAINT conversation_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE treatment_plan
    DROP CONSTRAINT treatment_plan_patient_id_fkey;
ALTER TABLE treatment_plan
    ADD CONSTRAINT treatment_plan_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE prescription
    DROP CONSTRAINT prescription_patient_id_fkey;
ALTER TABLE prescription
    ADD CONSTRAINT prescription_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE consultation_act
    DROP CONSTRAINT consultation_act_patient_id_fkey;
ALTER TABLE consultation_act
    ADD CONSTRAINT consultation_act_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE implant_passport
    DROP CONSTRAINT implant_passport_patient_id_fkey;
ALTER TABLE implant_passport
    ADD CONSTRAINT implant_passport_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE reminder
    DROP CONSTRAINT reminder_patient_id_fkey;
ALTER TABLE reminder
    ADD CONSTRAINT reminder_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE patient_tag
    DROP CONSTRAINT patient_tag_patient_id_fkey;
ALTER TABLE patient_tag
    ADD CONSTRAINT patient_tag_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE periodontal_chart
    DROP CONSTRAINT periodontal_chart_patient_id_fkey;
ALTER TABLE periodontal_chart
    ADD CONSTRAINT periodontal_chart_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE dental_chart_history
    DROP CONSTRAINT dental_chart_history_patient_id_fkey;
ALTER TABLE dental_chart_history
    ADD CONSTRAINT dental_chart_history_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);

ALTER TABLE orthodontic_treatment
    DROP CONSTRAINT orthodontic_treatment_patient_id_fkey;
ALTER TABLE orthodontic_treatment
    ADD CONSTRAINT orthodontic_treatment_patient_id_cabinet_fkey
    FOREIGN KEY (patient_id, cabinet_id)
    REFERENCES patient (id, cabinet_id);
