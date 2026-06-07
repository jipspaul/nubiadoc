-- 0078_clinical_note_kind_tooth.sql
-- Ajoute les colonnes `note_kind` et `tooth` à `clinical_note`.
-- Requises par POST /v1/cabinet/patients/:id/notes (issue #661).
-- `note_kind` : 'observation' | 'act' — obligatoire, défaut 'observation' pour rétro-compat.
-- `tooth` : numérotation ISO 3950, optionnelle.
-- `act_ref` : JSONB { label, ccam?, quote_item_id? } — optionnel, réservé aux notes de type 'act'.

ALTER TABLE clinical_note
  ADD COLUMN IF NOT EXISTS note_kind text NOT NULL DEFAULT 'observation'
    CHECK (note_kind IN ('observation', 'act')),
  ADD COLUMN IF NOT EXISTS tooth      text,
  ADD COLUMN IF NOT EXISTS act_ref    jsonb;
