-- #4291 : FK RLS-bypass — groupe "practitioner" (parent).
-- Postgres ignore RLS pour les contraintes FK/UNIQUE/PK (comportement documenté) :
-- une session scopée cabinet B peut référencer un practitioner_id de cabinet A
-- via un simple FK, même invisible en SELECT sous la même GUC app.current_cabinet_id.
-- Fix : FK composite (child_col, cabinet_id) REFERENCES practitioner(id, cabinet_id).
--
-- availability_slot est EXCLU de ce lot : c'est une projection publique
-- marketplace scopée provider_id (pas cabinet_id/practitioner_id) — concept de
-- tenant différent, hors périmètre de cet audit RLS cabinet.

ALTER TABLE practitioner
  ADD CONSTRAINT practitioner_id_cabinet_uniq UNIQUE (id, cabinet_id);

-- appointment.practitioner_id (NOT NULL)
ALTER TABLE appointment DROP CONSTRAINT appointment_practitioner_id_fkey;
ALTER TABLE appointment
  ADD CONSTRAINT appointment_practitioner_id_cabinet_fkey
  FOREIGN KEY (practitioner_id, cabinet_id) REFERENCES practitioner (id, cabinet_id);

-- treatment_plan.practitioner_id (nullable — NULL bypass FK check, sans régression)
ALTER TABLE treatment_plan DROP CONSTRAINT treatment_plan_practitioner_id_fkey;
ALTER TABLE treatment_plan
  ADD CONSTRAINT treatment_plan_practitioner_id_cabinet_fkey
  FOREIGN KEY (practitioner_id, cabinet_id) REFERENCES practitioner (id, cabinet_id);

-- prescription.practitioner_id (NOT NULL)
ALTER TABLE prescription DROP CONSTRAINT prescription_practitioner_id_fkey;
ALTER TABLE prescription
  ADD CONSTRAINT prescription_practitioner_id_cabinet_fkey
  FOREIGN KEY (practitioner_id, cabinet_id) REFERENCES practitioner (id, cabinet_id);

-- consultation_act.practitioner_id (NOT NULL)
ALTER TABLE consultation_act DROP CONSTRAINT consultation_act_practitioner_id_fkey;
ALTER TABLE consultation_act
  ADD CONSTRAINT consultation_act_practitioner_id_cabinet_fkey
  FOREIGN KEY (practitioner_id, cabinet_id) REFERENCES practitioner (id, cabinet_id);

-- consultation_session.practitioner_id (NOT NULL)
ALTER TABLE consultation_session DROP CONSTRAINT consultation_session_practitioner_id_fkey;
ALTER TABLE consultation_session
  ADD CONSTRAINT consultation_session_practitioner_id_cabinet_fkey
  FOREIGN KEY (practitioner_id, cabinet_id) REFERENCES practitioner (id, cabinet_id);

-- consultation_clinique.practitioner_id (NOT NULL)
ALTER TABLE consultation_clinique DROP CONSTRAINT consultation_clinique_practitioner_id_fkey;
ALTER TABLE consultation_clinique
  ADD CONSTRAINT consultation_clinique_practitioner_id_cabinet_fkey
  FOREIGN KEY (practitioner_id, cabinet_id) REFERENCES practitioner (id, cabinet_id);

-- prescription_template.practitioner_id (nullable, cabinet_id nullable aussi —
-- templates globaux : les deux NULL. MATCH SIMPLE : la contrainte ne protège
-- que les lignes où practitioner_id ET cabinet_id sont renseignés, ce qui est
-- strictement mieux que le FK simple précédent, sans rien casser.)
ALTER TABLE prescription_template DROP CONSTRAINT prescription_template_practitioner_id_fkey;
ALTER TABLE prescription_template
  ADD CONSTRAINT prescription_template_practitioner_id_cabinet_fkey
  FOREIGN KEY (practitioner_id, cabinet_id) REFERENCES practitioner (id, cabinet_id);

-- practitioner_favorite_act.practitioner_id (NOT NULL)
ALTER TABLE practitioner_favorite_act DROP CONSTRAINT practitioner_favorite_act_practitioner_id_fkey;
ALTER TABLE practitioner_favorite_act
  ADD CONSTRAINT practitioner_favorite_act_practitioner_id_cabinet_fkey
  FOREIGN KEY (practitioner_id, cabinet_id) REFERENCES practitioner (id, cabinet_id);
