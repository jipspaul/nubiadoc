-- 0043_app_user_cgu.sql
-- Ajoute cgu_accepted_at sur app_user : date d'acceptation des CGU.
-- NULL = CGU non encore acceptées (comptes créés avant la feature ou en attente).
-- Issue : #718

ALTER TABLE app_user
  ADD COLUMN cgu_accepted_at TIMESTAMPTZ;

COMMENT ON COLUMN app_user.cgu_accepted_at IS
  'Horodatage UTC d''acceptation des CGU. NULL = CGU non acceptées.';
