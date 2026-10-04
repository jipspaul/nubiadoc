-- 0308_refresh_token_replaced_by.sql
-- Rotation concurrente du refresh token (deux onglets qui partagent le même
-- localStorage et présentent le même refresh token en même temps) : il faut
-- distinguer un token révoqué par rotation normale (bénin, l'autre onglet
-- a juste perdu la course) d'un token révoqué explicitement (logout, ou
-- révocation en chaîne suite à un vol détecté). Seul ce dernier cas doit
-- déclencher la révocation de toute la chaîne de sessions.
-- Issue : #7883

ALTER TABLE refresh_token
    ADD COLUMN replaced_by_hash text;

COMMENT ON COLUMN refresh_token.replaced_by_hash IS
    'Hash du refresh token émis en remplacement lors d''une rotation. NULL si la révocation ne vient pas d''une rotation (logout, révocation en chaîne). Issue #7883.';
