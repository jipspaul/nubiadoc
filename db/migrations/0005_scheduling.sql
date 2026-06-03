-- 0005_scheduling.sql
-- Rendez-vous & file d'attente. Réf. : docs/05 §5.4.
-- ⭐ Contrainte d'exclusion anti-double-booking (nécessite btree_gist, cf. 0001) :
--    un praticien ne peut avoir deux RDV qui se chevauchent, hors annulés/no_show.
--    L'API mappe la violation en 409 slot_taken (docs/12 §7).

CREATE TABLE appointment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  patient_id      uuid NOT NULL REFERENCES patient(id),
  practitioner_id uuid NOT NULL REFERENCES practitioner(id),
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz NOT NULL,
  status          text NOT NULL CHECK (status IN
                    ('requested','confirmed','checked_in','in_progress','done','cancelled','no_show')),
  motif           text,
  pre_checkin     jsonb NOT NULL DEFAULT '{}',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,
  CONSTRAINT appointment_time_order CHECK (ends_at > starts_at),
  -- pas de double-booking praticien (créneaux actifs uniquement)
  CONSTRAINT appointment_no_overlap EXCLUDE USING gist (
    practitioner_id WITH =,
    tstzrange(starts_at, ends_at) WITH &&
  ) WHERE (status NOT IN ('cancelled','no_show'))
);

CREATE TABLE checkin_event (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id     uuid NOT NULL REFERENCES cabinet(id),
  appointment_id uuid NOT NULL REFERENCES appointment(id),
  mode           text NOT NULL CHECK (mode IN ('qr_app','qr_web','borne','sms')),
  occurred_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE waiting_list_entry (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id     uuid NOT NULL REFERENCES cabinet(id),
  patient_id     uuid NOT NULL REFERENCES patient(id),
  desired_window jsonb NOT NULL DEFAULT '{}',
  score          numeric(6,2) NOT NULL DEFAULT 0,
  status         text NOT NULL DEFAULT 'active'
                   CHECK (status IN ('active','fulfilled','cancelled')),
  created_at     timestamptz NOT NULL DEFAULT now()
);
