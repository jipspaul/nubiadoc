-- 0116_availability_slot_patient_read.sql
-- RLS policy availability_slot_patient_read : lecture publique des créneaux réservables
-- par les patients (status='available').
-- La policy existante slot_public_read (0059) couvre status='open' (marketplace).
-- Cette policy ajoute un accès public aux créneaux status='available' pour le booking
-- direct depuis le cabinet — sans GUC requis (fail-open, comme slot_public_read).
-- Issue : #2513

-- Étend la contrainte CHECK status pour autoriser 'available' (en plus de open/held/booked).
ALTER TABLE availability_slot DROP CONSTRAINT IF EXISTS availability_slot_status_check;
ALTER TABLE availability_slot ADD CONSTRAINT availability_slot_status_check
  CHECK (status IN ('open', 'held', 'booked', 'available'));

-- Policy SELECT publique : toute lecture sans restriction de rôle ni de GUC.
-- USING (status = 'available') — seuls les créneaux libres sont exposés.
CREATE POLICY availability_slot_patient_read ON availability_slot
  FOR SELECT
  USING (status = 'available');
