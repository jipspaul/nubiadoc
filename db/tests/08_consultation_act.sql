-- 08_consultation_act.sql — RLS consultation_act + appointment completion.
-- Réf. : issue #655, migration 0042.
-- Vérifie : isolement cross-tenant (négatif), insertion même-tenant (positif),
--           appointment_completion scoped, secrétariat fail-closed (0 actes visibles).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures : deux cabinets, un praticien dans A, un patient et un appointment.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'dc000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('dc000000-0000-0000-0000-000000000001', 'Cabinet CCAM A');

SET LOCAL app.current_cabinet_id = 'dc000000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('dc000000-0000-0000-0000-000000000002', 'Cabinet CCAM B');

-- app_user : entité plateforme, pas de RLS cabinet
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('dc000000-0000-0000-0000-00000000000a', 'pract.ccam@example.test', '$argon2id$x', 'pro');

SET LOCAL app.current_cabinet_id = 'dc000000-0000-0000-0000-000000000001';

INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('dc000000-0000-0000-0000-000000000010',
          'dc000000-0000-0000-0000-000000000001', 'Denise', 'CCAM');

INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('dc000000-0000-0000-0000-000000000020',
          'dc000000-0000-0000-0000-000000000001',
          'dc000000-0000-0000-0000-00000000000a');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
  VALUES ('dc000000-0000-0000-0000-000000000030',
          'dc000000-0000-0000-0000-000000000001',
          'dc000000-0000-0000-0000-000000000010',
          'dc000000-0000-0000-0000-000000000020',
          '2026-07-01 09:00:00+00', '2026-07-01 09:30:00+00', 'in_progress');

-- ===========================================================================
-- 1. CROSS-TENANT (négatif) : contexte cabinet B, cabinet_id cible = A → refusé
-- ===========================================================================
SET LOCAL app.current_cabinet_id      = 'dc000000-0000-0000-0000-000000000002';
SET LOCAL app.current_practitioner_id = 'dc000000-0000-0000-0000-000000000020';

SELECT throws_ok(
  $$ INSERT INTO consultation_act
       (cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents)
     VALUES ('dc000000-0000-0000-0000-000000000001',
             'dc000000-0000-0000-0000-000000000030',
             'dc000000-0000-0000-0000-000000000010',
             'dc000000-0000-0000-0000-000000000020',
             'DC0003', 'Extraction', 8500) $$,
  '42501', NULL,
  '⭐ cross-tenant : insertion consultation_act depuis contexte B vers cabinet A refusée');

-- ===========================================================================
-- 2. MÊME-TENANT (positif) : cabinet A, praticien A → insertion réussie
-- ===========================================================================
SET LOCAL app.current_cabinet_id      = 'dc000000-0000-0000-0000-000000000001';
SET LOCAL app.current_practitioner_id = 'dc000000-0000-0000-0000-000000000020';

INSERT INTO consultation_act
  (id, cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents)
VALUES
  ('dc000000-0000-0000-0000-000000000040',
   'dc000000-0000-0000-0000-000000000001',
   'dc000000-0000-0000-0000-000000000030',
   'dc000000-0000-0000-0000-000000000010',
   'dc000000-0000-0000-0000-000000000020',
   'DC0003', 'Extraction simple', 8500);

SELECT is(
  (SELECT count(*)::int FROM consultation_act
   WHERE id = 'dc000000-0000-0000-0000-000000000040'),
  1,
  'même-tenant + praticien : insertion consultation_act réussie (CCAM tracé)');

-- ===========================================================================
-- 3. APPOINTMENT COMPLETION : started_at posé dans le contexte praticien
-- ===========================================================================
UPDATE appointment
  SET started_at = '2026-07-01 09:05:00+00'
  WHERE id = 'dc000000-0000-0000-0000-000000000030';

SELECT is(
  (SELECT started_at IS NOT NULL
   FROM appointment WHERE id = 'dc000000-0000-0000-0000-000000000030'),
  true,
  'appointment_completion : started_at posé par le praticien (policy appointment_completion)');

-- ===========================================================================
-- 4. SECRÉTARIAT FAIL-CLOSED : sans current_practitioner_id → 0 actes visibles
-- ===========================================================================
SET LOCAL app.current_cabinet_id      = 'dc000000-0000-0000-0000-000000000001';
SET LOCAL app.current_practitioner_id = '';

SELECT is(
  (SELECT count(*)::int FROM consultation_act),
  0,
  '⭐ secrétariat fail-closed : 0 actes CCAM visibles sans current_practitioner_id');

SELECT * FROM finish();
ROLLBACK;
