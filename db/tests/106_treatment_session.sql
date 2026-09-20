-- 106_treatment_session.sql
-- pgTAP : treatment_session / treatment_session_act / cabinet_session_rules
-- (migration 0288, #7174).
--   TS1.  Cabinet A crée une séance + un acte réalisé rattaché (XOR OK).
--   TS2.  Rattacher une séance à un treatment_plan d'un AUTRE cabinet refusé (23503).
--   TS3.  Rattacher une séance à un appointment d'un AUTRE cabinet refusé (23503).
--   TS4.  Rattacher un acte à une treatment_session d'un AUTRE cabinet refusé (23503).
--   TS5.  treatment_session_act_source_xor : les deux sources renseignées refusé (23514).
--   TS6.  treatment_session_act_source_xor : aucune source renseignée refusé (23514).
--   TS7.  UNIQUE (plan_id, position) : deux séances à la même position refusé (23505).
--   TS8.  RLS treatment_session : cabinet B ne voit pas la séance de A.
--   TS9.  Fail-closed : sans GUC → 0 ligne treatment_session.
--   TS10. cabinet_session_rules : une seule ligne par cabinet (23505).
--   TS11. RLS cabinet_session_rules : cabinet B ne voit pas la règle de A.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71740000.
-- Issue : #7174

BEGIN;
SELECT plan(11);

-- ===========================================================================
-- Fixtures : 2 cabinets. Cabinet A avec patient/practitioner/treatment_plan/
-- appointment/consultation_act/quote/quote_item.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71740000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71740000-0000-0000-0000-000000000c01', 'Cabinet Session-7174-A');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71740000-0000-0000-0000-000000000a01', 'praticien.7174@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO practitioner (id, cabinet_id, user_id) VALUES
  ('71740000-0000-0000-0000-000000000b01', '71740000-0000-0000-0000-000000000c01',
   '71740000-0000-0000-0000-000000000a01');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71740000-0000-0000-0000-0000000000e1', '71740000-0000-0000-0000-000000000c01',
   'Patient', 'Session7174');
INSERT INTO treatment_plan (id, cabinet_id, patient_id, title) VALUES
  ('71740000-0000-0000-0000-00000000aa01', '71740000-0000-0000-0000-000000000c01',
   '71740000-0000-0000-0000-0000000000e1', 'Plan A');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) VALUES
  ('71740000-0000-0000-0000-00000000ad01', '71740000-0000-0000-0000-000000000c01',
   '71740000-0000-0000-0000-0000000000e1', '71740000-0000-0000-0000-000000000b01',
   '2026-10-01 09:00+00', '2026-10-01 09:30+00', 'confirmed');
INSERT INTO consultation_act (id, cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents) VALUES
  ('71740000-0000-0000-0000-00000000ca01', '71740000-0000-0000-0000-000000000c01',
   '71740000-0000-0000-0000-00000000ad01', '71740000-0000-0000-0000-0000000000e1',
   '71740000-0000-0000-0000-000000000b01', 'HBJD001', 'Obturation', 8000);
INSERT INTO quote (id, cabinet_id, patient_id) VALUES
  ('71740000-0000-0000-0000-00000000cc01', '71740000-0000-0000-0000-000000000c01',
   '71740000-0000-0000-0000-0000000000e1');
INSERT INTO quote_item (id, cabinet_id, quote_id, label, unit_amount) VALUES
  ('71740000-0000-0000-0000-00000000dd01', '71740000-0000-0000-0000-000000000c01',
   '71740000-0000-0000-0000-00000000cc01', 'Acte devisé', 8000);
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71740000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71740000-0000-0000-0000-000000000c02', 'Cabinet Session-7174-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- TS1. Cabinet A crée une séance sur son propre plan/RDV + un acte réalisé
-- rattaché (consultation_act_id seul renseigné).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71740000-0000-0000-0000-000000000c01';
INSERT INTO treatment_session (id, cabinet_id, plan_id, position, duration_min, appointment_id) VALUES
  ('71740000-0000-0000-0000-000000005e01', '71740000-0000-0000-0000-000000000c01',
   '71740000-0000-0000-0000-00000000aa01', 1, 30, '71740000-0000-0000-0000-00000000ad01');
INSERT INTO treatment_session_act (id, cabinet_id, session_id, consultation_act_id) VALUES
  ('71740000-0000-0000-0000-000000005a01', '71740000-0000-0000-0000-000000000c01',
   '71740000-0000-0000-0000-000000005e01', '71740000-0000-0000-0000-00000000ca01');
SELECT is(
  (SELECT count(*)::int FROM treatment_session_act
   WHERE id = '71740000-0000-0000-0000-000000005a01'),
  1,
  'TS1 treatment_session/treatment_session_act : création cabinet A, séance + acte rattachés OK');

-- ===========================================================================
-- TS2. Rattacher une séance à un treatment_plan d'un AUTRE cabinet refusé
-- (23503) — treatment_plan a RLS+FORCE RLS : la ligne de A est invisible
-- sous le GUC B, la FK échoue avant toute policy.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71740000-0000-0000-0000-000000000c02';
SELECT throws_ok(
  $$ INSERT INTO treatment_session (cabinet_id, plan_id, position, duration_min)
     VALUES ('71740000-0000-0000-0000-000000000c02',
             '71740000-0000-0000-0000-00000000aa01', 9, 30) $$,
  '23503', NULL,
  '⭐ TS2 treatment_session : rattacher un plan d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- TS3. Rattacher une séance à un appointment d'un AUTRE cabinet refusé
-- (23503). Nécessite un plan valide côté B pour isoler l'échec sur le FK
-- appointment.
-- ===========================================================================
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('71740000-0000-0000-0000-0000000000e2', '71740000-0000-0000-0000-000000000c02',
   'Patient', 'Session7174B');
INSERT INTO treatment_plan (id, cabinet_id, patient_id, title) VALUES
  ('71740000-0000-0000-0000-00000000aa02', '71740000-0000-0000-0000-000000000c02',
   '71740000-0000-0000-0000-0000000000e2', 'Plan B');
SELECT throws_ok(
  $$ INSERT INTO treatment_session (cabinet_id, plan_id, position, duration_min, appointment_id)
     VALUES ('71740000-0000-0000-0000-000000000c02',
             '71740000-0000-0000-0000-00000000aa02', 1, 30,
             '71740000-0000-0000-0000-00000000ad01') $$,
  '23503', NULL,
  '⭐ TS3 treatment_session : rattacher un appointment d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- TS4. Rattacher un acte à une treatment_session d'un AUTRE cabinet refusé
-- (23503).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO treatment_session_act (cabinet_id, session_id, quote_item_id)
     VALUES ('71740000-0000-0000-0000-000000000c02',
             '71740000-0000-0000-0000-000000005e01',
             '71740000-0000-0000-0000-00000000dd01') $$,
  '23503', NULL,
  '⭐ TS4 treatment_session_act : rattacher une session d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- TS5/TS6. treatment_session_act_source_xor : exactement une source.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71740000-0000-0000-0000-000000000c01';
SELECT throws_ok(
  $$ INSERT INTO treatment_session_act (cabinet_id, session_id, consultation_act_id, quote_item_id)
     VALUES ('71740000-0000-0000-0000-000000000c01',
             '71740000-0000-0000-0000-000000005e01',
             '71740000-0000-0000-0000-00000000ca01',
             '71740000-0000-0000-0000-00000000dd01') $$,
  '23514', NULL,
  'TS5 treatment_session_act_source_xor : consultation_act_id + quote_item_id renseignés refusé (23514)');

SELECT throws_ok(
  $$ INSERT INTO treatment_session_act (cabinet_id, session_id)
     VALUES ('71740000-0000-0000-0000-000000000c01',
             '71740000-0000-0000-0000-000000005e01') $$,
  '23514', NULL,
  'TS6 treatment_session_act_source_xor : aucune source renseignée refusé (23514)');

-- ===========================================================================
-- TS7. UNIQUE (plan_id, position) : deux séances à la même position sur le
-- même plan refusé (23505).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO treatment_session (cabinet_id, plan_id, position, duration_min)
     VALUES ('71740000-0000-0000-0000-000000000c01',
             '71740000-0000-0000-0000-00000000aa01', 1, 20) $$,
  '23505', NULL,
  'TS7 treatment_session_plan_id_position_key : position dupliquée sur le même plan refusée (23505)');

-- ===========================================================================
-- TS8. RLS treatment_session : cabinet B ne voit PAS la séance de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71740000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM treatment_session
   WHERE id = '71740000-0000-0000-0000-000000005e01'),
  0,
  '⭐ TS8 tenant_isolation treatment_session : cabinet B ne voit PAS la séance de A');

-- ===========================================================================
-- TS9. Fail-closed : sans GUC → 0 ligne sur treatment_session.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM treatment_session),
  0,
  '⭐ TS9 fail-closed : 0 ligne treatment_session sans GUC positionné');

-- ===========================================================================
-- TS10. cabinet_session_rules : une seule ligne par cabinet (23505).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71740000-0000-0000-0000-000000000c01';
INSERT INTO cabinet_session_rules (id, cabinet_id, max_duration_min, separate_arches, group_by_sector, multi_endo) VALUES
  ('71740000-0000-0000-0000-00000000c501', '71740000-0000-0000-0000-000000000c01',
   60, true, true, false);
SELECT throws_ok(
  $$ INSERT INTO cabinet_session_rules (cabinet_id, max_duration_min)
     VALUES ('71740000-0000-0000-0000-000000000c01', 45) $$,
  '23505', NULL,
  'TS10 cabinet_session_rules_cabinet_uniq : deuxième ligne pour le même cabinet refusée (23505)');

-- ===========================================================================
-- TS11. RLS cabinet_session_rules : cabinet B ne voit PAS la règle de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71740000-0000-0000-0000-000000000c02';
SELECT is(
  (SELECT count(*)::int FROM cabinet_session_rules
   WHERE id = '71740000-0000-0000-0000-00000000c501'),
  0,
  '⭐ TS11 tenant_isolation cabinet_session_rules : cabinet B ne voit PAS la règle de A');

SELECT * FROM finish();
ROLLBACK;
