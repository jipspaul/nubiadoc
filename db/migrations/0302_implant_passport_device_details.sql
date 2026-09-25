-- 0302_implant_passport_device_details.sql
-- Passeport implantaire (0072) : ajoute les champs d'identification dispositif
-- et de suivi que la fiche patient (`GET /v1/implant-passport`) doit exposer
-- mais que le schéma initial ne portait pas — fabricant/modèle/référence
-- distincts de `brand`, dimensions, matériau, compatibilité IRM, dernier
-- contrôle et prochain contrôle recommandé.
-- Toutes nullable : donnée non chiffrée (pas de PII directe, même statut que
-- `brand`/`lot_number`/`notes`, cf. 0072), absente sur les implants existants
-- tant qu'un praticien ne l'a pas renseignée.
-- Issue : #7665

ALTER TABLE implant_passport
    ADD COLUMN manufacturer      text,
    ADD COLUMN model             text,
    ADD COLUMN reference         text,
    ADD COLUMN dimensions        text,
    ADD COLUMN material          text,
    ADD COLUMN mri_compatibility text,
    ADD COLUMN last_control_date date,
    ADD COLUMN next_control      text;

COMMENT ON COLUMN implant_passport.manufacturer IS
    'Fabricant du dispositif, distinct de `brand` (nom commercial). Issue #7665.';
COMMENT ON COLUMN implant_passport.model IS
    'Modèle du dispositif (ex. ''Replace Select Tapered''). Issue #7665.';
COMMENT ON COLUMN implant_passport.reference IS
    'Référence commerciale affichée au patient, distincte de `implant_ref` (traçabilité médico-légale interne). Issue #7665.';
COMMENT ON COLUMN implant_passport.dimensions IS
    'Dimensions du dispositif (ex. ''Ø 4,3 mm · L 11,5 mm''). Issue #7665.';
COMMENT ON COLUMN implant_passport.material IS
    'Matériau du dispositif (ex. ''Titane grade 4'') — donnée demandée avant tout examen d''imagerie. Issue #7665.';
COMMENT ON COLUMN implant_passport.mri_compatibility IS
    'Compatibilité IRM du dispositif (ex. ''Compatible IRM sous conditions''). Issue #7665.';
COMMENT ON COLUMN implant_passport.last_control_date IS
    'Date du dernier contrôle de suivi de l''implant. Issue #7665.';
COMMENT ON COLUMN implant_passport.next_control IS
    'Libellé du prochain contrôle recommandé (ex. ''Mars 2027 · annuel''). Issue #7665.';
