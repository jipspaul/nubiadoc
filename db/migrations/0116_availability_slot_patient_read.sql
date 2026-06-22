-- 0116_availability_slot_patient_read.sql
-- Policy RLS availability_slot_patient_read : lecture publique des créneaux
-- disponibles (status='open') pour les patients cherchant à booker en ligne.
-- Permissive, sans GUC requis (fail-open sur 'open') — annuaire et booking.
-- Réf. : issue #2513 ; docs/05 §9.2 ; docs/12 §12.4.

CREATE POLICY availability_slot_patient_read ON availability_slot
  FOR SELECT
  USING (status = 'open');
