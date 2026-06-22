-- 0116_availability_slot_patient_read.sql
-- Policy RLS availability_slot_patient_read : lecture publique des créneaux
-- disponibles (status = 'available') pour le flux de réservation patient.
-- Étend le CHECK de statut pour inclure la valeur 'available' (créneau réservable
-- via le module booking, distinct de 'open' utilisé par le marketplace).
-- Issue : #2513

-- Étend la contrainte CHECK status pour inclure 'available'
ALTER TABLE availability_slot
  DROP CONSTRAINT availability_slot_status_check;

ALTER TABLE availability_slot
  ADD CONSTRAINT availability_slot_status_check
    CHECK (status IN ('open', 'available', 'held', 'booked'));

-- Lecture publique patient : seuls les créneaux 'available' sont visibles.
-- S'applique à tous les rôles (pas de clause TO) — pas de GUC requis (non fail-closed).
CREATE POLICY availability_slot_patient_read ON availability_slot
  FOR SELECT
  USING (status = 'available');
