-- 0074_cabinet_slots_bo.sql
-- Gestion des créneaux BO : ajoute cabinet_id + practitioner_id + online_booking à
-- availability_slot, contrainte d'exclusion anti-double-booking praticien, et policy
-- RLS cabinet pour les opérations d'écriture BO (POST/PATCH/DELETE/PUT).
-- Réf. : docs/12 §13 ; issue #814.
--
-- Avant cette migration, availability_slot n'avait que provider_id (marketplace).
-- La policy slot_public_read (0059) reste : SELECT status='open' côté marketplace.
-- On ajoute deux policies cabinet pour le BO :
--   slot_cabinet_write : INSERT/UPDATE/DELETE scoped par cabinet_id (opérateurs BO).
--   slot_cabinet_read  : SELECT scoped par cabinet_id (agenda interne complet).
-- Ainsi nubia_app peut gérer SES créneaux (tous statuts) sans voir ceux d'autres cabinets.

-- Colonnes nécessaires au BO
ALTER TABLE availability_slot
  ADD COLUMN IF NOT EXISTS cabinet_id      uuid REFERENCES cabinet(id),
  ADD COLUMN IF NOT EXISTS practitioner_id uuid REFERENCES practitioner(id),
  ADD COLUMN IF NOT EXISTS online_booking  boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS created_at      timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at      timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS deleted_at      timestamptz;

-- Contrainte d'exclusion anti-double-booking praticien (btree_gist déjà activé en 0001).
-- Un praticien ne peut avoir deux créneaux qui se chevauchent, hors booked/supprimés.
ALTER TABLE availability_slot
  ADD CONSTRAINT slot_practitioner_no_overlap
    EXCLUDE USING gist (
      practitioner_id WITH =,
      tstzrange(starts_at, ends_at) WITH &&
    ) WHERE (practitioner_id IS NOT NULL AND status <> 'booked' AND deleted_at IS NULL);

-- Index cabinet+praticien+temps pour les requêtes BO
CREATE INDEX IF NOT EXISTS slot_cabinet_practitioner_time_idx
  ON availability_slot (cabinet_id, practitioner_id, starts_at)
  WHERE deleted_at IS NULL;

-- RLS cabinet pour le BO (lecture interne + écriture)
CREATE POLICY slot_cabinet_read ON availability_slot
  FOR SELECT TO nubia_app
  USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY slot_cabinet_write ON availability_slot
  FOR ALL TO nubia_app
  USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
  WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- seed : accès complet pour les données démo (policy élargie au-delà de slot_seed 0059)
-- La policy slot_seed (0059) couvre déjà ALL pour nubia_seed — aucun ajout nécessaire.
