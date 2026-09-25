-- 116_staff_planning.sql
-- pgTAP : staff_shift, leave_request, time_clock_entry (#7145, migration 0300).
--   ST1-2.  Tables présentes, RLS ENABLE + FORCE sur les 3 tables.
--   ST3-4.  staff_shift : CHECK range (23514), insertion valide cabinet A.
--   ST5-8.  leave_request : CHECK range (23514), kind hors énum (23514),
--           status hors énum (23514), insertion valide cabinet A.
--   ST9-10. time_clock_entry : CHECK range (23514), source hors énum (23514).
--   ST11.   time_clock_entry : insertion valide cabinet A.
--   ST12-14. Fail-closed : sans GUC, 0 ligne sur les 3 tables.
--   ST15-20. Cross-tenant (cabinet B) : non-fuite en lecture + WITH CHECK
--            refuse l'écriture cross-cabinet (42501), sur les 3 tables.
--   ST21-23. Contexte A : les 3 lignes restent visibles dans leur propre cabinet.
--   ST24.   leave_request : décision (approved + decided_by) appliquée.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71450000.
-- Issue : #7145

BEGIN;
SELECT plan(24);

-- ===========================================================================
-- Fixtures : cabinet A (staff + decider) et cabinet B.
-- ===========================================================================
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71450000-0000-0000-0000-0000000000a1', 'staff.7145@nubia.test', '$argon2id$fixture', 'pro'),
  ('71450000-0000-0000-0000-0000000000a2', 'manager.7145@nubia.test', '$argon2id$fixture', 'pro'),
  ('71450000-0000-0000-0000-0000000000b1', 'staff.b.7145@nubia.test', '$argon2id$fixture', 'pro');

SET LOCAL app.current_cabinet_id = '71450000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71450000-0000-0000-0000-000000000c01', 'Cabinet Planning-7145-A');
INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES
  ('71450000-0000-0000-0000-000000000c01', '71450000-0000-0000-0000-0000000000a1', 'secretary'),
  ('71450000-0000-0000-0000-000000000c01', '71450000-0000-0000-0000-0000000000a2', 'admin');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71450000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71450000-0000-0000-0000-000000000c02', 'Cabinet Planning-7145-B');
INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES
  ('71450000-0000-0000-0000-000000000c02', '71450000-0000-0000-0000-0000000000b1', 'secretary');
RESET app.current_cabinet_id;

-- ===========================================================================
-- ST1-2. RLS ENABLE + FORCE sur les 3 tables.
-- ===========================================================================
SELECT ok(
  (SELECT bool_and(relrowsecurity AND relforcerowsecurity)
   FROM pg_class WHERE relname IN ('staff_shift', 'leave_request', 'time_clock_entry')),
  'ST1 staff_shift/leave_request/time_clock_entry : RLS ENABLE + FORCE activées');
SELECT ok(
  (SELECT count(*)::int FROM pg_policies
   WHERE tablename IN ('staff_shift', 'leave_request', 'time_clock_entry')
     AND policyname = 'tenant_isolation') = 3,
  'ST2 : policy tenant_isolation présente sur les 3 tables');

-- ===========================================================================
-- ST3-4. staff_shift : CHECK range + insertion valide (cabinet A).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71450000-0000-0000-0000-000000000c01';

SELECT throws_ok(
  $$ INSERT INTO staff_shift (cabinet_id, user_id, starts_at, ends_at)
     VALUES ('71450000-0000-0000-0000-000000000c01',
             '71450000-0000-0000-0000-0000000000a1',
             now() + interval '2 hours', now()) $$,
  '23514', NULL,
  'ST3 staff_shift_check_range : starts_at >= ends_at rejeté (23514)');

INSERT INTO staff_shift (id, cabinet_id, user_id, starts_at, ends_at, room) VALUES
  ('71450000-0000-0000-0000-000000000101', '71450000-0000-0000-0000-000000000c01',
   '71450000-0000-0000-0000-0000000000a1',
   '2026-02-02 08:00:00+00', '2026-02-02 16:00:00+00', 'Salle 1');
SELECT is(
  (SELECT count(*)::int FROM staff_shift WHERE id = '71450000-0000-0000-0000-000000000101'),
  1,
  'ST4 staff_shift : insertion cabinet A OK');

-- ===========================================================================
-- ST5-8. leave_request : CHECK range, kind/status hors énum, insertion valide.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO leave_request (cabinet_id, user_id, starts_at, ends_at, kind)
     VALUES ('71450000-0000-0000-0000-000000000c01',
             '71450000-0000-0000-0000-0000000000a1',
             now() + interval '2 days', now() + interval '1 day', 'paid_leave') $$,
  '23514', NULL,
  'ST5 leave_request_check_range : starts_at >= ends_at rejeté (23514)');

SELECT throws_ok(
  $$ INSERT INTO leave_request (cabinet_id, user_id, starts_at, ends_at, kind)
     VALUES ('71450000-0000-0000-0000-000000000c01',
             '71450000-0000-0000-0000-0000000000a1',
             now() + interval '1 day', now() + interval '2 days', 'vacances') $$,
  '23514', NULL,
  'ST6 leave_request : kind hors énum rejeté (23514)');

SELECT throws_ok(
  $$ INSERT INTO leave_request (cabinet_id, user_id, starts_at, ends_at, kind, status)
     VALUES ('71450000-0000-0000-0000-000000000c01',
             '71450000-0000-0000-0000-0000000000a1',
             now() + interval '1 day', now() + interval '2 days', 'paid_leave', 'brouillon') $$,
  '23514', NULL,
  'ST7 leave_request : status hors énum rejeté (23514)');

INSERT INTO leave_request (id, cabinet_id, user_id, starts_at, ends_at, kind) VALUES
  ('71450000-0000-0000-0000-000000000201', '71450000-0000-0000-0000-000000000c01',
   '71450000-0000-0000-0000-0000000000a1',
   '2026-03-10 00:00:00+00', '2026-03-15 00:00:00+00', 'paid_leave');
SELECT is(
  (SELECT status FROM leave_request WHERE id = '71450000-0000-0000-0000-000000000201'),
  'pending',
  'ST8 leave_request : insertion cabinet A OK, status par défaut pending');

-- ===========================================================================
-- ST9-11. time_clock_entry : CHECK range, source hors énum, insertion valide.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO time_clock_entry (cabinet_id, user_id, clock_in, clock_out)
     VALUES ('71450000-0000-0000-0000-000000000c01',
             '71450000-0000-0000-0000-0000000000a1',
             now(), now() - interval '1 hour') $$,
  '23514', NULL,
  'ST9 time_clock_entry_check_range : clock_out <= clock_in rejeté (23514)');

SELECT throws_ok(
  $$ INSERT INTO time_clock_entry (cabinet_id, user_id, clock_in, source)
     VALUES ('71450000-0000-0000-0000-000000000c01',
             '71450000-0000-0000-0000-0000000000a1',
             now(), 'robot') $$,
  '23514', NULL,
  'ST10 time_clock_entry : source hors énum rejeté (23514)');

INSERT INTO time_clock_entry (id, cabinet_id, user_id, clock_in, source) VALUES
  ('71450000-0000-0000-0000-000000000301', '71450000-0000-0000-0000-000000000c01',
   '71450000-0000-0000-0000-0000000000a1', '2026-02-02 07:55:00+00', 'badge');
SELECT is(
  (SELECT count(*)::int FROM time_clock_entry WHERE id = '71450000-0000-0000-0000-000000000301'),
  1,
  'ST11 time_clock_entry : insertion cabinet A OK');

-- ===========================================================================
-- ST12-14. Fail-closed : sans GUC → 0 ligne sur les 3 tables.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM staff_shift WHERE id = '71450000-0000-0000-0000-000000000101'),
  0, '⭐ ST12 fail-closed : staff_shift invisible sans app.current_cabinet_id');
SELECT is(
  (SELECT count(*)::int FROM leave_request WHERE id = '71450000-0000-0000-0000-000000000201'),
  0, '⭐ ST13 fail-closed : leave_request invisible sans app.current_cabinet_id');
SELECT is(
  (SELECT count(*)::int FROM time_clock_entry WHERE id = '71450000-0000-0000-0000-000000000301'),
  0, '⭐ ST14 fail-closed : time_clock_entry invisible sans app.current_cabinet_id');

-- ===========================================================================
-- ST15-20. Cross-tenant (cabinet B) : non-fuite lecture + WITH CHECK écriture.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71450000-0000-0000-0000-000000000c02';

SELECT is(
  (SELECT count(*)::int FROM staff_shift WHERE id = '71450000-0000-0000-0000-000000000101'),
  0, '⭐ ST15 non-fuite : cabinet B ne voit pas le shift du cabinet A');
SELECT throws_ok(
  $$ INSERT INTO staff_shift (cabinet_id, user_id, starts_at, ends_at)
     VALUES ('71450000-0000-0000-0000-000000000c01',
             '71450000-0000-0000-0000-0000000000b1',
             now() + interval '1 day', now() + interval '1 day 1 hour') $$,
  '42501', NULL,
  '⭐ ST16 WITH CHECK : insertion staff_shift cross-cabinet refusée depuis contexte B');

SELECT is(
  (SELECT count(*)::int FROM leave_request WHERE id = '71450000-0000-0000-0000-000000000201'),
  0, '⭐ ST17 non-fuite : cabinet B ne voit pas la demande de congé du cabinet A');
SELECT throws_ok(
  $$ INSERT INTO leave_request (cabinet_id, user_id, starts_at, ends_at, kind)
     VALUES ('71450000-0000-0000-0000-000000000c01',
             '71450000-0000-0000-0000-0000000000b1',
             now() + interval '1 day', now() + interval '2 days', 'paid_leave') $$,
  '42501', NULL,
  '⭐ ST18 WITH CHECK : insertion leave_request cross-cabinet refusée depuis contexte B');

SELECT is(
  (SELECT count(*)::int FROM time_clock_entry WHERE id = '71450000-0000-0000-0000-000000000301'),
  0, '⭐ ST19 non-fuite : cabinet B ne voit pas le pointage du cabinet A');
SELECT throws_ok(
  $$ INSERT INTO time_clock_entry (cabinet_id, user_id, clock_in)
     VALUES ('71450000-0000-0000-0000-000000000c01',
             '71450000-0000-0000-0000-0000000000b1', now()) $$,
  '42501', NULL,
  '⭐ ST20 WITH CHECK : insertion time_clock_entry cross-cabinet refusée depuis contexte B');

-- ===========================================================================
-- ST21-23. Contexte A : les 3 lignes restent visibles dans leur propre cabinet.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71450000-0000-0000-0000-000000000c01';
SELECT is(
  (SELECT count(*)::int FROM staff_shift WHERE id = '71450000-0000-0000-0000-000000000101'),
  1, 'ST21 contexte A : shift visible dans le bon cabinet');
SELECT is(
  (SELECT count(*)::int FROM leave_request WHERE id = '71450000-0000-0000-0000-000000000201'),
  1, 'ST22 contexte A : demande de congé visible dans le bon cabinet');
SELECT is(
  (SELECT count(*)::int FROM time_clock_entry WHERE id = '71450000-0000-0000-0000-000000000301'),
  1, 'ST23 contexte A : pointage visible dans le bon cabinet');

-- ===========================================================================
-- ST24. Décision leave_request : approbation par le manager (decided_by).
-- ===========================================================================
UPDATE leave_request
  SET status = 'approved', decided_by = '71450000-0000-0000-0000-0000000000a2'
  WHERE id = '71450000-0000-0000-0000-000000000201';
SELECT is(
  (SELECT status FROM leave_request WHERE id = '71450000-0000-0000-0000-000000000201'),
  'approved',
  'ST24 leave_request : décision approved + decided_by appliquée');

SELECT * FROM finish();
ROLLBACK;
