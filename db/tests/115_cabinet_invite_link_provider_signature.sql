-- 115_cabinet_invite_link_provider_signature.sql
-- pgTAP : cabinet_invite_link + provider.signature_image_id/stamp_image_id
-- (migration 0299, #7149, DP-F25.a).
--   CIL1. Cabinet A crée un lien d'invitation (role='practitioner') OK.
--   CIL2. role hors énumération refusé (23514).
--   CIL3. max_uses <= 0 refusé (23514).
--   CIL4. uses > max_uses refusé (23514, cabinet_invite_link_uses_within_max).
--   CIL5. token dupliqué refusé (23505).
--   CIL6. ⭐ RLS ouverte : résolution par token visible SANS aucun GUC cabinet
--         positionné (visiteur anonyme découvrant l'invitation) — à l'inverse
--         du fail-closed des autres tables tenant, par design (cf. 0299).
--   CIL7. ⭐ nubia_app : DELETE refusé (42501) — révocation via revoked_at/
--         expires_at uniquement, jamais un DELETE SQL.
--   PSG1. document.category accepte 'signature' (insert OK).
--   PSG2. document.category accepte 'tampon' (insert OK).
--   PSG3. provider.signature_image_id : rattachement OK.
--   PSG4. provider.stamp_image_id : rattachement OK.
--   PSG5. provider.signature_image_id référençant un document inexistant
--         refusé (23503).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71490000.
-- Issue : #7149

BEGIN;
SELECT plan(12);

-- ===========================================================================
-- Fixtures : 1 cabinet, 1 app_user praticien, 1 provider.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71490000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71490000-0000-0000-0000-000000000c01', 'Cabinet InviteLink-7149');

INSERT INTO app_user (id, email, password_hash, kind, status) VALUES
  ('71490000-0000-0000-0000-0000000000a1', 'prat.7149@nubia.test', '$argon2id$fixture', 'pro', 'active');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) VALUES
  ('71490000-0000-0000-0000-0000000000b1', '71490000-0000-0000-0000-000000000c01',
   '71490000-0000-0000-0000-0000000000a1', 'Dr Signature-7149', false, false);

-- ===========================================================================
-- CIL1. Cabinet A crée un lien d'invitation (role='practitioner') OK.
-- ===========================================================================
INSERT INTO cabinet_invite_link (id, cabinet_id, role, token, expires_at, max_uses, created_by) VALUES
  ('71490000-0000-0000-0000-000000004101', '71490000-0000-0000-0000-000000000c01',
   'practitioner', 'tok-7149-aaaa', now() + interval '7 days', 3,
   '71490000-0000-0000-0000-0000000000a1');
SELECT is(
  (SELECT count(*)::int FROM cabinet_invite_link
   WHERE id = '71490000-0000-0000-0000-000000004101'),
  1,
  'CIL1 cabinet_invite_link : création cabinet A (role=practitioner) OK');

-- ===========================================================================
-- CIL2. role hors énumération refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_invite_link (cabinet_id, role, token, expires_at)
     VALUES ('71490000-0000-0000-0000-000000000c01',
             'superadmin', 'tok-7149-bad-role', now() + interval '7 days') $$,
  '23514', NULL,
  'CIL2 cabinet_invite_link_role_check : role hors énumération refusé (23514)');

-- ===========================================================================
-- CIL3. max_uses <= 0 refusé (23514).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_invite_link (cabinet_id, role, token, expires_at, max_uses)
     VALUES ('71490000-0000-0000-0000-000000000c01',
             'secretary', 'tok-7149-bad-maxuses', now() + interval '7 days', 0) $$,
  '23514', NULL,
  'CIL3 cabinet_invite_link_max_uses_check : max_uses=0 refusé (23514)');

-- ===========================================================================
-- CIL4. uses > max_uses refusé (23514, cabinet_invite_link_uses_within_max).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_invite_link (cabinet_id, role, token, expires_at, max_uses, uses)
     VALUES ('71490000-0000-0000-0000-000000000c01',
             'secretary', 'tok-7149-bad-uses', now() + interval '7 days', 1, 2) $$,
  '23514', NULL,
  '⭐ CIL4 cabinet_invite_link_uses_within_max : uses > max_uses refusé (23514)');

-- ===========================================================================
-- CIL5. token dupliqué refusé (23505).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_invite_link (cabinet_id, role, token, expires_at)
     VALUES ('71490000-0000-0000-0000-000000000c01',
             'secretary', 'tok-7149-aaaa', now() + interval '7 days') $$,
  '23505', NULL,
  'CIL5 cabinet_invite_link_token_uniq : token dupliqué refusé (23505)');

-- ===========================================================================
-- CIL6. ⭐ RLS ouverte : résolution par token visible sans GUC cabinet.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM cabinet_invite_link WHERE token = 'tok-7149-aaaa'),
  1,
  '⭐ CIL6 cabinet_invite_link_app_all : résolution par token visible sans GUC (visiteur anonyme, by design)');

-- ===========================================================================
-- CIL7. ⭐ nubia_app : DELETE refusé (42501) — révocation via revoked_at/expires_at.
-- ===========================================================================
SELECT throws_ok(
  $$ DELETE FROM cabinet_invite_link WHERE token = 'tok-7149-aaaa' $$,
  '42501', NULL,
  '⭐ CIL7 cabinet_invite_link : DELETE refusé pour nubia_app (42501, révocation via revoked_at)');

SET LOCAL app.current_cabinet_id = '71490000-0000-0000-0000-000000000c01';

-- ===========================================================================
-- PSG1. document.category accepte 'signature'.
-- ===========================================================================
INSERT INTO document (id, cabinet_id, category, storage_key, filename, mime_type, sha256, uploaded_by) VALUES
  ('71490000-0000-0000-0000-000000005101', '71490000-0000-0000-0000-000000000c01',
   'signature', '7149/signature.png', 'signature.png', 'image/png', repeat('a', 64),
   '71490000-0000-0000-0000-0000000000a1');
SELECT is(
  (SELECT category FROM document WHERE id = '71490000-0000-0000-0000-000000005101'),
  'signature',
  'PSG1 document_category_check : category=''signature'' acceptée (0299)');

-- ===========================================================================
-- PSG2. document.category accepte 'tampon'.
-- ===========================================================================
INSERT INTO document (id, cabinet_id, category, storage_key, filename, mime_type, sha256, uploaded_by) VALUES
  ('71490000-0000-0000-0000-000000005102', '71490000-0000-0000-0000-000000000c01',
   'tampon', '7149/tampon.png', 'tampon.png', 'image/png', repeat('b', 64),
   '71490000-0000-0000-0000-0000000000a1');
SELECT is(
  (SELECT category FROM document WHERE id = '71490000-0000-0000-0000-000000005102'),
  'tampon',
  'PSG2 document_category_check : category=''tampon'' acceptée (0299)');

-- ===========================================================================
-- PSG3. provider.signature_image_id : rattachement OK.
-- ===========================================================================
UPDATE provider
  SET signature_image_id = '71490000-0000-0000-0000-000000005101',
      stamp_image_id     = '71490000-0000-0000-0000-000000005102'
  WHERE id = '71490000-0000-0000-0000-0000000000b1';
SELECT is(
  (SELECT signature_image_id FROM provider WHERE id = '71490000-0000-0000-0000-0000000000b1'),
  '71490000-0000-0000-0000-000000005101'::uuid,
  'PSG3 provider.signature_image_id : rattachement au document OK');

-- ===========================================================================
-- PSG4. provider.stamp_image_id : rattachement OK.
-- ===========================================================================
SELECT is(
  (SELECT stamp_image_id FROM provider WHERE id = '71490000-0000-0000-0000-0000000000b1'),
  '71490000-0000-0000-0000-000000005102'::uuid,
  'PSG4 provider.stamp_image_id : rattachement au document OK');

-- ===========================================================================
-- PSG5. provider.signature_image_id référençant un document inexistant refusé (23503).
-- ===========================================================================
SELECT throws_ok(
  $$ UPDATE provider SET signature_image_id = '71490000-0000-0000-0000-0000000000ff'
     WHERE id = '71490000-0000-0000-0000-0000000000b1' $$,
  '23503', NULL,
  'PSG5 provider_signature_image_id_fkey : document inexistant refusé (23503)');

RESET app.current_cabinet_id;
SELECT * FROM finish();
ROLLBACK;
