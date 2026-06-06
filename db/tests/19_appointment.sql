-- 19_appointment.sql — RLS appointment : double-booking + isolation tenant.
-- Complémente 01_constraints.sql (EXCLUDE gist) et 03_rls.sql (isolation générique).
-- Vérifie explicitement l'isolation cross-cabinet et le fail-closed pour appointment.
-- Issue #824.
BEGIN;
SELECT * FROM no_plan();

-- ---------------------------------------------------------------------------
-- Fixtures : cabinet A et B, chacun avec praticien + patient + un RDV.
-- ---------------------------------------------------------------------------
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES ('a0000000-0000-0000-0000-000000000001','Cabinet A');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('a0000000-0000-0000-0000-0000000000a1','prat.a@appt.test','$argon2id$fixture','pro');
INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('a0000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000a1');
INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('a0000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','Alice','A');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
  VALUES ('a0000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-000000000001',
          'a0000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-0000000000c1',
          '2026-06-20 09:00+00','2026-06-20 09:30+00','confirmed');

SET LOCAL app.current_cabinet_id = 'b0000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES ('b0000000-0000-0000-0000-000000000001','Cabinet B');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('b0000000-0000-0000-0000-0000000000a1','prat.b@appt.test','$argon2id$fixture','pro');
INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('b0000000-0000-0000-0000-0000000000c1','b0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-0000000000a1');
INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('b0000000-0000-0000-0000-0000000000d1','b0000000-0000-0000-0000-000000000001','Bob','B');
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
  VALUES ('b0000000-0000-0000-0000-0000000000e1','b0000000-0000-0000-0000-000000000001',
          'b0000000-0000-0000-0000-0000000000d1','b0000000-0000-0000-0000-0000000000c1',
          '2026-06-20 09:00+00','2026-06-20 09:30+00','confirmed');

-- ===========================================================================
-- 1. Isolation READ : contexte A → 1 RDV visible, aucun RDV de B.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
SELECT is( (SELECT count(*)::int FROM appointment), 1,
  '⭐ contexte A : 1 RDV visible');
SELECT is( (SELECT count(*)::int FROM appointment
             WHERE cabinet_id = 'b0000000-0000-0000-0000-000000000001'), 0,
  '⭐ non-fuite : contexte A ne voit AUCUN RDV de B');

-- ===========================================================================
-- 2. Isolation READ : contexte B → 1 RDV visible, aucun RDV de A.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'b0000000-0000-0000-0000-000000000001';
SELECT is( (SELECT count(*)::int FROM appointment), 1,
  '⭐ contexte B : 1 RDV visible');
SELECT is( (SELECT count(*)::int FROM appointment
             WHERE cabinet_id = 'a0000000-0000-0000-0000-000000000001'), 0,
  '⭐ non-fuite : contexte B ne voit AUCUN RDV de A');

-- ===========================================================================
-- 3. WITH CHECK : écriture cross-tenant refusée (contexte B, target cabinet A).
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('a0000000-0000-0000-0000-000000000001',
             'a0000000-0000-0000-0000-0000000000d1',
             'a0000000-0000-0000-0000-0000000000c1',
             '2026-06-20 14:00+00','2026-06-20 14:30+00','confirmed') $$,
  '42501', NULL, '⭐ WITH CHECK : insertion appointment dans un autre cabinet refusée');

-- ===========================================================================
-- 4. Fail-closed : sans GUC → aucun RDV visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is( (SELECT count(*)::int FROM appointment), 0,
  '⭐ fail-closed : aucun RDV visible sans app.current_cabinet_id');

SELECT * FROM finish();
ROLLBACK;
