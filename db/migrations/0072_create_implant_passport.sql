-- 0072_create_implant_passport.sql
-- Passeport implantaire patient : suivi des implants dentaires posés.
-- Marque, référence, lot, date pose, position FDI, notes.
-- Données non chiffrées (pas de PII directe).
-- RLS dans migration séparée (0073).
-- Issue : #699

CREATE TABLE implant_passport (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id       uuid        NOT NULL REFERENCES cabinet(id),
    patient_id       uuid        NOT NULL REFERENCES patient(id),
    implant_ref      text        NOT NULL,
    brand            text        NOT NULL,
    lot_number       text,
    placement_date   date,
    tooth_position   text,
    notes            text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    deleted_at       timestamptz
);

CREATE INDEX idx_implant_passport_cabinet_patient
    ON implant_passport (cabinet_id, patient_id);

COMMENT ON TABLE implant_passport IS
    'Passeport implantaire (multi-tenant, RLS via cabinet_id). Issue #699.';
COMMENT ON COLUMN implant_passport.tooth_position IS
    'Position dentaire en notation FDI (ex. ''26'').';
COMMENT ON COLUMN implant_passport.implant_ref IS
    'Référence commerciale de l''implant (ex. SKU fabricant).';
