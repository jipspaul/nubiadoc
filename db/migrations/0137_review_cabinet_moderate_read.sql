-- 0137_review_cabinet_moderate_read.sql
-- `review_app_update` (migration 0059) autorise l'UPDATE (pending→published/rejected)
-- mais PATCH /v1/cabinet/reviews/:id échoue en 404 systématique : pour UPDATE,
-- Postgres exige aussi qu'une policy SELECT rende la ligne visible, or les
-- seules policies SELECT existantes sur `review` sont review_patient_read
-- (auteur du patient) et review_public_read (status='published') — un avis
-- 'pending' n'est donc jamais visible par le cabinet qui doit le modérer.
-- Permissive (OR) : rend visibles au cabinet propriétaire du provider les avis
-- (quel que soit leur statut) via `app.current_cabinet_id`, même pattern que
-- document_cabinet_read_via_patient_account (migration 0135).
-- Issue : #3503

CREATE POLICY review_cabinet_moderate_read ON review
  FOR SELECT
  TO nubia_app
  USING (
    provider_id IN (
      SELECT id FROM provider
      WHERE cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
    )
  );
