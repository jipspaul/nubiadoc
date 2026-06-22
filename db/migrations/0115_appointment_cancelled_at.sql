-- 0115_appointment_cancelled_at.sql
-- La colonne cancelled_at existe déjà depuis 0031_appointment_cancel_columns.
-- Cette migration ajoute uniquement l'index partiel WHERE status='cancelled'
-- pour accélérer les requêtes analytiques sur les annulations.
-- Issue : #2512

CREATE INDEX idx_appointment_cancelled_at
  ON appointment(cancelled_at)
  WHERE status = 'cancelled';
