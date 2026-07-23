-- 0199_medical_questionnaire_submission_cabinet_review.sql
-- Fix RLS pour #4356 (dupe #4350) : POST .../medical-questionnaire/review
-- renvoie TOUJOURS 500 sur une soumission legitimement 'submitted'.
--
-- Root cause : 0180 ne pose que 2 policies sur medical_questionnaire_submission :
--   - medical_questionnaire_submission_patient_owner (FOR ALL, USING
--     patient_account_id = app.patient_account_id) -> faux en contexte
--     cabinet (le praticien ne pose jamais app.patient_account_id).
--   - medical_questionnaire_submission_cabinet_read (FOR SELECT uniquement)
--     -> ne couvre pas l'UPDATE.
-- review_medical_questionnaire (medical_questionnaire.rs:480-489) execute
-- un UPDATE ... SET status='reviewed' ... RETURNING en contexte cabinet
-- (seul app.current_cabinet_id est pose) : aucune policy RLS n'autorise
-- cet UPDATE -> 0 ligne modifiee -> RowNotFound -> 500. La ligne est meme
-- lisible (policy _cabinet_read), seule l'ecriture manque.
--
-- Fix : policy UPDATE dediee, cabinet + status='submitted' uniquement (le
-- cabinet ne peut jamais toucher un brouillon en cours de saisie ni une
-- soumission deja reviewed - meme garde-fou que le handler applicatif,
-- defense en profondeur). WITH CHECK ne re-verifie que l'appartenance au
-- cabinet (la transition de statut elle-meme reste controlee par le code).

CREATE POLICY medical_questionnaire_submission_cabinet_review
    ON medical_questionnaire_submission
    FOR UPDATE
    TO nubia_app
    USING (
        cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
        AND status = 'submitted'
    )
    WITH CHECK (
        cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
    );
