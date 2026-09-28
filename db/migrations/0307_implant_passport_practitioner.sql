-- 0307_implant_passport_practitioner.sql
-- Passeport implantaire (0072) : le document de traçabilité doit nommer le
-- praticien qui a posé l'implant (maquette design-v2, écrans ① et ②) — champ
-- absent à tous les niveaux de la pile alors que le front l'attend déjà
-- (`ImplantItemDto.practitioner`). Nullable : absent sur les implants
-- existants tant qu'un praticien ne l'a pas posé via ce chemin (même statut
-- que `lot_number`/`notes`, cf. 0072).
-- Issue : #6924

ALTER TABLE implant_passport
    ADD COLUMN practitioner_id uuid REFERENCES practitioner(id);

COMMENT ON COLUMN implant_passport.practitioner_id IS
    'Praticien ayant posé l''implant — nom exposé au patient via practitioner_person_name() (migration 0304). Issue #6924.';
