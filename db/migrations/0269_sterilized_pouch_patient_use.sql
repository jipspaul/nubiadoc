-- 0269_sterilized_pouch_patient_use.sql
-- DP-F13.a (#7181) : rattachement d'un sachet stérilisé à un PATIENT par scan
-- (`POST /v1/sterilization/pouches/:code/use`). Jusqu'ici la traçabilité
-- lot ↔ patient passait uniquement par `consultation_act_id` (migration
-- 0190) — un sachet ouvert au fauteuil AVANT la saisie des actes (cas
-- courant : le plateau est préparé, le QR scanné, l'acte codé après) ne
-- pouvait pas être tracé.
--
-- On complète `sterilized_pouch` (pas de seconde table : un sachet est à
-- usage unique, une seule utilisation par ligne — l'unicité du code par
-- cabinet, migration 0191, porte déjà cette règle) :
--   - `patient_id`      : patient sur lequel le sachet a été ouvert ;
--   - `consultation_id` : séance (`consultation_session`) où il a été
--                         ouvert, optionnelle ;
--   - `used_at`/`used_by` : horodatage et acteur du scan.
--
-- FK COMPOSITES `(x_id, cabinet_id)` pour patient et consultation_session
-- (mêmes raisons que 0190/0198 : PostgreSQL bypasse la RLS pour les
-- vérifications FK — une FK simple laisserait le cabinet B référencer un
-- patient du cabinet A). Les index uniques cibles existent déjà :
-- `patient_id_cabinet_uniq` (0193) et `consultation_session_id_cabinet_uniq`
-- (0211).
--
-- Invariant : `used_at` est posé si et seulement si `patient_id` l'est
-- (CHECK) — un sachet est « utilisé » dès qu'il est rattaché à un patient,
-- la consultation seule ne suffit pas.

ALTER TABLE sterilized_pouch
    ADD COLUMN patient_id      uuid,
    ADD COLUMN consultation_id uuid,
    ADD COLUMN used_at         timestamptz,
    ADD COLUMN used_by         uuid REFERENCES app_user (id),
    ADD CONSTRAINT sterilized_pouch_patient_id_cabinet_fkey
        FOREIGN KEY (patient_id, cabinet_id)
        REFERENCES patient (id, cabinet_id),
    ADD CONSTRAINT sterilized_pouch_consultation_id_cabinet_fkey
        FOREIGN KEY (consultation_id, cabinet_id)
        REFERENCES consultation_session (id, cabinet_id),
    ADD CONSTRAINT sterilized_pouch_used_at_with_patient_chk
        CHECK ((patient_id IS NULL) = (used_at IS NULL));

CREATE INDEX idx_sterilized_pouch_patient
    ON sterilized_pouch (patient_id)
    WHERE patient_id IS NOT NULL;

COMMENT ON COLUMN sterilized_pouch.patient_id IS
    'Patient sur lequel le sachet a été ouvert (scan au fauteuil, #7181). NULL tant que le sachet n''est pas utilisé.';
COMMENT ON COLUMN sterilized_pouch.consultation_id IS
    'Séance (consultation_session) où le sachet a été ouvert, optionnelle. #7181.';
COMMENT ON COLUMN sterilized_pouch.used_at IS
    'Horodatage du scan d''utilisation (posé avec patient_id). #7181.';
COMMENT ON COLUMN sterilized_pouch.used_by IS
    'Utilisateur ayant scanné l''utilisation du sachet. #7181.';
