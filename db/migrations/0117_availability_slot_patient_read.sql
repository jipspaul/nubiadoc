-- 0116_availability_slot_patient_read.sql
-- Policy RLS availability_slot_patient_read : lecture publique des créneaux
-- disponibles (status='open') pour le parcours booking patient.
-- La table availability_slot est hors tenant cabinet ; aucun GUC requis.
-- Un patient quelconque (et toute personne) peut voir les slots 'open' sans
-- contexte d'authentification — fail-open voulu (annuaire/booking public).
-- Les slots 'held' et 'booked' restent invisibles (policy permissive filtrée).
-- Issue : #2513

CREATE POLICY availability_slot_patient_read ON availability_slot
  FOR SELECT
  USING (status = 'open');
