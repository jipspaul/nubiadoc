-- 0118_patient_account_avatar.sql
-- Photo de profil du compte patient (petite image, stockée en ligne — pas
-- d'Object Storage nécessaire pour un avatar ≤ 300 Ko ; pas de PII clinique).
-- Lecture/écriture par le porteur du compte uniquement (RLS existante
-- patient_account self via app.patient_account_id + policies user_self_*).

ALTER TABLE patient_account
    ADD COLUMN IF NOT EXISTS avatar bytea,
    ADD COLUMN IF NOT EXISTS avatar_mime text;

COMMENT ON COLUMN patient_account.avatar IS
    'Photo de profil (binaire ≤ 300 Ko, contrôlé côté API). NULL = pas d''avatar.';
COMMENT ON COLUMN patient_account.avatar_mime IS
    'Type MIME de l''avatar (image/jpeg, image/png, image/webp).';
