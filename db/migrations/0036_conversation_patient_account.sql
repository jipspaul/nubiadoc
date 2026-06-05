-- 0036_conversation_patient_account.sql
-- Ajoute patient_account_id à conversation pour le lien plateforme et la contrainte
-- d'unicité par couple (patient_account × cabinet). Issue #450 : POST /v1/conversations.
-- patient_id devient nullable : la liaison clinique peut arriver après la prise de contact.

ALTER TABLE conversation
    ADD COLUMN IF NOT EXISTS patient_account_id uuid REFERENCES patient_account(id);

ALTER TABLE conversation
    ALTER COLUMN patient_id DROP NOT NULL;

ALTER TABLE conversation
    ADD CONSTRAINT conversation_uniq_patient_account_cabinet
    UNIQUE (patient_account_id, cabinet_id);
