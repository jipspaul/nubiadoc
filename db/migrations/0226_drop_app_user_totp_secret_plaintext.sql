-- 0226_drop_app_user_totp_secret_plaintext.sql
-- Supprime `app_user.totp_secret` (colonne TEXT en clair, migration 0014) :
-- depuis #4652, l'API n'écrit/ne lit plus le secret TOTP que via
-- `mfa_enrollment.secret_ciphertext` (chiffré KMS, migration 0046/0047).
-- Cette colonne n'était donc plus qu'un résidu en clair (#4653).
--
-- Backfill : les lignes historiques où `totp_secret` était encore
-- renseigné (pré-#4652, secret jamais migré/chiffré vers `mfa_enrollment`)
-- ne peuvent pas être ré-encryptées ici — le chiffrement KMS est une
-- opération applicative (core-crypto), inaccessible depuis une migration
-- SQL pure. On réinitialise donc la MFA pour ces comptes (ré-enrôlement
-- requis au prochain login) plutôt que de laisser un secret en clair
-- traîner en base : `totp_enabled = false` pour les utilisateurs sans
-- enrôlement chiffré correspondant dans `mfa_enrollment`.
-- Issue : #4653

UPDATE app_user
SET totp_enabled = false
WHERE totp_secret IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM mfa_enrollment
    WHERE mfa_enrollment.app_user_id = app_user.id
      AND mfa_enrollment.method = 'totp'
  );

ALTER TABLE app_user DROP COLUMN totp_secret;
