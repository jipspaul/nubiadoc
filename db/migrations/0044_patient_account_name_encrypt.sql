-- 0044_patient_account_name_encrypt.sql
-- Ajoute les colonnes chiffrées first_name / last_name sur patient_account.
-- L'application stocke ici le prénom/nom chiffrés (core/crypto, clé par utilisateur) ;
-- les colonnes plaintext restent pour rétro-compatibilité jusqu'à migration applicative.
-- Schéma chiffrement : bytea + key_ref, contrainte de cohérence paire.
-- Issue : #718

ALTER TABLE patient_account
  ADD COLUMN first_name_ciphertext BYTEA,
  ADD COLUMN first_name_key_ref    TEXT,
  ADD COLUMN last_name_ciphertext  BYTEA,
  ADD COLUMN last_name_key_ref     TEXT,
  ADD CONSTRAINT patient_account_fn_crypto_pair
    CHECK ((first_name_ciphertext IS NULL) = (first_name_key_ref IS NULL)),
  ADD CONSTRAINT patient_account_ln_crypto_pair
    CHECK ((last_name_ciphertext IS NULL) = (last_name_key_ref IS NULL));

COMMENT ON COLUMN patient_account.first_name_ciphertext IS
  'Prénom chiffré applicatif (core/crypto). NULL jusqu''à migration des lignes existantes.';
COMMENT ON COLUMN patient_account.last_name_ciphertext IS
  'Nom chiffré applicatif (core/crypto). NULL jusqu''à migration des lignes existantes.';
