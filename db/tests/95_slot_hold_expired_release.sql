-- 95_slot_hold_expired_release.sql
-- pgTAP : libération des holds de créneau expirés (#6992 / #6840, migration 0272).
--   SHE1. Hold ACTIF : le créneau `held` reste invisible en lecture publique (sans GUC)
--   SHE2. Hold ACTIF : slot_hold_expired() = false
--   SHE3. Hold EXPIRÉ : slot_hold_expired() = true (SECURITY DEFINER, sans GUC cabinet)
--   SHE4. Hold EXPIRÉ : le créneau `held` redevient visible en lecture publique (policy slot_public_read_expired_hold)
--   SHE5. `held` SANS ligne slot_holds : reste invisible en lecture publique
--   SHE6. release_expired_slot_holds() purge exactement le hold expiré (retour = 1)
--   SHE7. … et repasse son créneau en `open`
--   SHE8. … le hold expiré a disparu de slot_holds
--   SHE9. … le hold ACTIF est intact (créneau toujours `held`)
--   SHE10. Seconde passe : no-op (retour = 0)
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 69920000.
-- Issue : #6992, #6840

BEGIN;
SELECT plan(10);

-- ===========================================================================
-- Fixtures : cabinet + provider + 3 créneaux (hold actif / hold expiré /
-- held orphelin) + patient.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '69920000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
  ('69920000-0000-0000-0000-000000000001', 'Cabinet HoldExpiry-6992');

INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('69920000-0000-0000-0000-0000000000a1', 'pro-6992@nubia.test', 'hash', 'pro'),
  ('69920000-0000-0000-0000-0000000000a2', 'patient-6992@nubia.test', 'hash', 'patient');

INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) VALUES
  ('69920000-0000-0000-0000-000000000101',
   '69920000-0000-0000-0000-000000000001',
   '69920000-0000-0000-0000-0000000000a1',
   'Dr HoldExpiry 6992', true, true);

INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status, online_booking) VALUES
  -- f1 : hold actif
  ('69920000-0000-0000-0000-0000000000f1',
   '69920000-0000-0000-0000-000000000101',
   '69920000-0000-0000-0000-000000000001',
   now() + interval '1 day', now() + interval '1 day 30 minutes', 'held', true),
  -- f2 : hold expiré
  ('69920000-0000-0000-0000-0000000000f2',
   '69920000-0000-0000-0000-000000000101',
   '69920000-0000-0000-0000-000000000001',
   now() + interval '2 days', now() + interval '2 days 30 minutes', 'held', true),
  -- f3 : held orphelin (aucune ligne slot_holds)
  ('69920000-0000-0000-0000-0000000000f3',
   '69920000-0000-0000-0000-000000000101',
   '69920000-0000-0000-0000-000000000001',
   now() + interval '3 days', now() + interval '3 days 30 minutes', 'held', true);

INSERT INTO slot_holds (id, slot_id, user_id, hold_token, expires_at) VALUES
  ('69920000-0000-0000-0000-000000000201',
   '69920000-0000-0000-0000-0000000000f1',
   '69920000-0000-0000-0000-0000000000a2',
   'hold-6992-active', now() + interval '10 minutes'),
  ('69920000-0000-0000-0000-000000000202',
   '69920000-0000-0000-0000-0000000000f2',
   '69920000-0000-0000-0000-0000000000a2',
   'hold-6992-expired', now() - interval '2 minutes');

-- ===========================================================================
-- Lecture publique (aucun GUC cabinet — comme /v1/search/slots).
-- ===========================================================================
RESET app.current_cabinet_id;

-- SHE1
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = '69920000-0000-0000-0000-0000000000f1'),
  0,
  'SHE1 hold actif : créneau held invisible en lecture publique');

-- SHE2
SELECT is(
  slot_hold_expired('69920000-0000-0000-0000-0000000000f1'),
  false,
  'SHE2 hold actif : slot_hold_expired() = false');

-- SHE3
SELECT is(
  slot_hold_expired('69920000-0000-0000-0000-0000000000f2'),
  true,
  'SHE3 hold expiré : slot_hold_expired() = true sans GUC cabinet');

-- SHE4
SELECT is(
  (SELECT count(*)::int FROM availability_slot sl
   WHERE sl.id = '69920000-0000-0000-0000-0000000000f2'
     AND (sl.status = 'open' OR (sl.status = 'held' AND slot_hold_expired(sl.id)))),
  1,
  'SHE4 hold expiré : créneau held visible en lecture publique (filtre expires_at)');

-- SHE5
SELECT is(
  (SELECT count(*)::int FROM availability_slot
   WHERE id = '69920000-0000-0000-0000-0000000000f3'),
  0,
  'SHE5 held orphelin (sans slot_holds) : reste invisible en lecture publique');

-- ===========================================================================
-- Reaper (hors contexte de requête : aucun GUC cabinet non plus).
-- ===========================================================================

-- SHE6
SELECT is(
  release_expired_slot_holds(),
  1,
  'SHE6 release_expired_slot_holds() purge exactement 1 hold (l''expiré)');

-- SHE7
SELECT is(
  (SELECT status FROM availability_slot
   WHERE id = '69920000-0000-0000-0000-0000000000f2'),
  'open',
  'SHE7 reaper : le créneau au hold expiré repasse en open');

SET LOCAL app.current_cabinet_id = '69920000-0000-0000-0000-000000000001';

-- SHE8
SELECT is(
  (SELECT count(*)::int FROM slot_holds
   WHERE id = '69920000-0000-0000-0000-000000000202'),
  0,
  'SHE8 reaper : le hold expiré a été supprimé');

-- SHE9
SELECT is(
  (SELECT status || '/' || (SELECT count(*)::text FROM slot_holds
                            WHERE id = '69920000-0000-0000-0000-000000000201')
   FROM availability_slot
   WHERE id = '69920000-0000-0000-0000-0000000000f1'),
  'held/1',
  'SHE9 reaper : le hold actif et son créneau held sont intacts');

RESET app.current_cabinet_id;

-- SHE10
SELECT is(
  release_expired_slot_holds(),
  0,
  'SHE10 seconde passe du reaper : no-op');

SELECT * FROM finish();
ROLLBACK;
