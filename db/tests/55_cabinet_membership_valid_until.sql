-- 55_cabinet_membership_valid_until.sql — Contrat de valid_until sur
-- cabinet_membership (#4157, gestion des remplaçants). user_all_memberships()
-- (SECURITY DEFINER, migration 0089/0162) est l'unique point d'authentification
-- qui résout les memberships d'un utilisateur pro — appelé par POST /v1/auth/login
-- et POST /v1/auth/select-context. Vérifie : membership permanent (valid_until
-- NULL) -> retourné · membership expiré (valid_until passé) -> absent ·
-- membership encore valide (valid_until futur) -> retourné · membership
-- expiré mais active=false de toute façon -> absent (comportement pré-existant
-- inchangé).
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK.

BEGIN;
SELECT * FROM no_plan();

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('05500000-0000-0000-0000-0000000000a1', 'remplacant-permanent-55@nubia.test', 'hash', 'pro'),
  ('05500000-0000-0000-0000-0000000000a2', 'remplacant-expire-55@nubia.test', 'hash', 'pro'),
  ('05500000-0000-0000-0000-0000000000a3', 'remplacant-valide-55@nubia.test', 'hash', 'pro')
  ON CONFLICT DO NOTHING;

SET LOCAL app.current_cabinet_id = '05500000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('05500000-0000-0000-0000-000000000001', 'Cabinet 55-valid-until')
  ON CONFLICT DO NOTHING;

INSERT INTO cabinet_membership (cabinet_id, user_id, role, active, valid_until) VALUES
  ('05500000-0000-0000-0000-000000000001', '05500000-0000-0000-0000-0000000000a1', 'practitioner', true, NULL),
  ('05500000-0000-0000-0000-000000000001', '05500000-0000-0000-0000-0000000000a2', 'practitioner', true, now() - interval '1 day'),
  ('05500000-0000-0000-0000-000000000001', '05500000-0000-0000-0000-0000000000a3', 'practitioner', true, now() + interval '1 day')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- Aucun GUC posé ici — exactement les conditions d'appel réelles (login/select-context).
SELECT is(
  (SELECT count(*)::int FROM user_all_memberships('05500000-0000-0000-0000-0000000000a1')),
  1,
  'valid_until NULL (permanent) -> membership retourné');

SELECT is(
  (SELECT count(*)::int FROM user_all_memberships('05500000-0000-0000-0000-0000000000a2')),
  0,
  '⭐ valid_until dans le passé -> membership absent (accès borné respecté)');

SELECT is(
  (SELECT count(*)::int FROM user_all_memberships('05500000-0000-0000-0000-0000000000a3')),
  1,
  'valid_until dans le futur -> membership encore retourné');

SELECT * FROM finish();
ROLLBACK;
