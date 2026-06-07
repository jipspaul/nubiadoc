-- 0076_review_constraints.sql
-- Anti-faux-avis : contrainte UNIQUE sur appointment_id (un RDV = un seul avis).
-- Ajout : idempotency_key pour POST /v1/reviews, author_display pour la réponse GET.
-- Policy RLS : lecture par le patient auteur (app.patient_account_id).
-- Réf. : docs/12 §12.4 ; issue #767.

-- Un RDV ne peut générer qu'un seul avis (anti-fake-reviews).
ALTER TABLE review
  ADD CONSTRAINT review_appointment_unique UNIQUE (appointment_id);

-- Idempotency-Key côté client pour POST /v1/reviews (rejeu sans doublon).
ALTER TABLE review
  ADD COLUMN idempotency_key text;

CREATE UNIQUE INDEX idx_review_idempotency_key
  ON review (patient_account_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- Nom affiché de l'auteur (prénom + initiale du nom, calculé à l'insertion).
ALTER TABLE review
  ADD COLUMN author_display text NOT NULL DEFAULT '';

-- Policy : le patient auteur peut lire ses propres avis (tous statuts).
-- Permissive : s'additionne à review_public_read (status = 'published').
CREATE POLICY review_patient_read ON review
  FOR SELECT TO nubia_app
  USING (
    patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
  );
