-- 0116_availability_slot_patient_read.sql
-- Ajoute le statut 'available' à availability_slot et la policy SELECT publique
-- permettant aux patients de lire les créneaux réservables (booking marketplace).
-- La contrainte inline non nommée (0009) est étendue pour inclure 'available'.
-- Issue : #2513

-- Étendre la contrainte de statut pour inclure 'available'
ALTER TABLE availability_slot
  DROP CONSTRAINT availability_slot_status_check;
ALTER TABLE availability_slot
  ADD CONSTRAINT availability_slot_status_check
    CHECK (status IN ('open', 'held', 'booked', 'available'));

-- Policy lecture publique patient : seuls les créneaux 'available' sont visibles.
-- Pas de dépendance au GUC app.current_cabinet_id (lecture publique, fail-open voulu).
CREATE POLICY availability_slot_patient_read ON availability_slot
  FOR SELECT
  USING (status = 'available');
