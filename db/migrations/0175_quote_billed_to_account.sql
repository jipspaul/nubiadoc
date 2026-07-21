-- 0175_quote_billed_to_account.sql
-- Facturation au responsable légal (#4098) : le rattachement enfants/parents
-- est construit (`account_guardianship`, migration 0025), mais `quote` ne
-- référence que le compte du bénéficiaire des soins (via `patient.
-- patient_account_id`) — aucun mécanisme n'impute la facturation au compte
-- du responsable. Colonne nullable, résolue côté API à la création
-- (api/src/cabinet_quotes.rs) via account_guardianship, jamais saisie
-- librement par le client.
--
-- Étend quote_patient_read (migration 0029, corrigée 0134 pour exclure les
-- brouillons — #3487) : un devis reste visible au bénéficiaire des soins
-- (comportement inchangé, EXCLUSION `draft` PRÉSERVÉE) ET, si
-- billed_to_account_id est renseigné, au compte facturé (le responsable
-- légal, même exclusion `draft`).

ALTER TABLE quote
    ADD COLUMN billed_to_account_id uuid REFERENCES patient_account(id);

DROP POLICY quote_patient_read ON quote;
CREATE POLICY quote_patient_read ON quote
    FOR SELECT
    TO nubia_app
    USING (
        status <> 'draft'
        AND (
            patient_id IN (
                SELECT id FROM patient
                WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
            )
            OR billed_to_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        )
    );

COMMENT ON COLUMN quote.billed_to_account_id IS 'Compte plateforme facturé (responsable légal), résolu via account_guardianship à la création — NULL si le bénéficiaire des soins est aussi le compte facturé. Issue #4098.';
