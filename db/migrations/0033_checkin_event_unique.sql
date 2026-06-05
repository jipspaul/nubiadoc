-- 0033_checkin_event_unique.sql
-- Contrainte UNIQUE sur checkin_event.appointment_id : un seul check-in par RDV.
-- Réf. : docs/12 §7 (règle métier check-in) ; issue #386.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'checkin_event_appointment_unique'
      AND conrelid = 'checkin_event'::regclass
  ) THEN
    ALTER TABLE checkin_event
      ADD CONSTRAINT checkin_event_appointment_unique UNIQUE (appointment_id);
  END IF;
END
$$;
