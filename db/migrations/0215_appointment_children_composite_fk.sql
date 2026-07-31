-- #4291 : FK RLS-bypass — groupe "appointment" (parent).
-- Même pattern que 0210-0214 : FK composite (child_col, cabinet_id)
-- REFERENCES appointment(id, cabinet_id).
-- appointment a déjà UNIQUE(id, cabinet_id) depuis 0193 (lab_work_order) —
-- pas besoin de la recréer ici.

-- checkin_event.appointment_id (NOT NULL)
ALTER TABLE checkin_event DROP CONSTRAINT checkin_event_appointment_id_fkey;
ALTER TABLE checkin_event
  ADD CONSTRAINT checkin_event_appointment_id_cabinet_fkey
  FOREIGN KEY (appointment_id, cabinet_id) REFERENCES appointment (id, cabinet_id);

-- consultation_act.appointment_id (NOT NULL)
ALTER TABLE consultation_act DROP CONSTRAINT consultation_act_appointment_id_fkey;
ALTER TABLE consultation_act
  ADD CONSTRAINT consultation_act_appointment_id_cabinet_fkey
  FOREIGN KEY (appointment_id, cabinet_id) REFERENCES appointment (id, cabinet_id);

-- consultation_session.appointment_id (NOT NULL)
ALTER TABLE consultation_session DROP CONSTRAINT consultation_session_appointment_id_fkey;
ALTER TABLE consultation_session
  ADD CONSTRAINT consultation_session_appointment_id_cabinet_fkey
  FOREIGN KEY (appointment_id, cabinet_id) REFERENCES appointment (id, cabinet_id);

-- reminder.appointment_id (NOT NULL)
ALTER TABLE reminder DROP CONSTRAINT reminder_appointment_id_fkey;
ALTER TABLE reminder
  ADD CONSTRAINT reminder_appointment_id_cabinet_fkey
  FOREIGN KEY (appointment_id, cabinet_id) REFERENCES appointment (id, cabinet_id);

-- consultation_clinique.appointment_id (NOT NULL UNIQUE — 1:1 avec appointment,
-- l'UNIQUE simple existant est inchangé, seule la FK devient composite).
ALTER TABLE consultation_clinique DROP CONSTRAINT consultation_clinique_appointment_id_fkey;
ALTER TABLE consultation_clinique
  ADD CONSTRAINT consultation_clinique_appointment_id_cabinet_fkey
  FOREIGN KEY (appointment_id, cabinet_id) REFERENCES appointment (id, cabinet_id);
