-- 08_consultation_act.sql — Tests RLS consultation_act + appointment completion.
-- Vérifie : fail-closed (secretary → 0 rows), isolation inter-cabinet,
-- WITH CHECK cross-tenant refusé, appointment.started_at scoped au tenant.
-- Issue : #651
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures (préfixe 65100000-... propre à cette suite, hors des 0040/seed)
-- ===========================================================================
-- app_user (entité plateforme, pas de RLS cabinet)
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('65100000-0000-0000-0000-0000000000a1',
          'practitioner.651@example.test', '$argon2id$fixture', 'pro');

-- Cabinet 651-A
SET LOCAL app.current_cabinet_id = '65100000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('65100000-0000-0000-0000-000000000001', 'Cabinet 651-A');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('65100000-0000-0000-0000-0000000000b1',
          '65100000-0000-0000-0000-000000000001', 'Eva', '651A');

INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('65100000-0000-0000-0000-0000000000c1',
          '65100000-0000-0000-0000-000000000001',
          '65100000-0000-0000-0000-0000000000a1');

INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id,
                         starts_at, ends_at, status)
  VALUES ('65100000-0000-0000-0000-0000000000d1',
          '65100000-0000-0000-0000-000000000001',
          '65100000-0000-0000-0000-0000000000b1',
          '65100000-0000-0000-0000-0000000000c1',
          '2025-06-01 09:00:00+00', '2025-06-01 10:00:00+00',
          'in_progress');

INSERT INTO consultation_act
    (id, cabinet_id, appointment_id, patient_id, practitioner_id,
     ccam_code, label, amount_cents)
  VALUES ('65100000-0000-0000-0000-0000000000e1',
          '65100000-0000-0000-0000-000000000001',
          '65100000-0000-0000-0000-0000000000d1',
          '65100000-0000-0000-0000-0000000000b1',
          '65100000-0000-0000-0000-0000000000c1',
          'HBLD001', 'Détartrage supragingival', 7500);

-- Cabinet 651-B (pour les tests cross-tenant)
SET LOCAL app.current_cabinet_id = '65100000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('65100000-0000-0000-0000-000000000002', 'Cabinet 651-B');

-- ===========================================================================
-- 1. FAIL-CLOSED : sans GUC positionné → 0 acte visible (secretary sans contexte).
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is( (SELECT count(*) FROM consultation_act
            WHERE id = '65100000-0000-0000-0000-0000000000e1')::int, 0,
  '⭐ fail-closed : aucun acte CCAM visible sans app.current_cabinet_id');

-- ===========================================================================
-- 2. MÊME-TENANT : contexte 651-A → 1 acte visible, bon ccam_code.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '65100000-0000-0000-0000-000000000001';
SELECT is( (SELECT count(*) FROM consultation_act
            WHERE cabinet_id = '65100000-0000-0000-0000-000000000001')::int, 1,
  'contexte 651-A : 1 acte CCAM visible');
SELECT is( (SELECT ccam_code FROM consultation_act
            WHERE id = '65100000-0000-0000-0000-0000000000e1'), 'HBLD001',
  'contexte 651-A : ccam_code correct');

-- ===========================================================================
-- 3. NON-FUITE : contexte 651-B → 0 acte de 651-A visible.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '65100000-0000-0000-0000-000000000002';
SELECT is( (SELECT count(*) FROM consultation_act
            WHERE cabinet_id = '65100000-0000-0000-0000-000000000001')::int, 0,
  '⭐ non-fuite : contexte 651-B ne voit aucun acte du cabinet 651-A');

-- ===========================================================================
-- 4. WITH CHECK : insertion cross-tenant refusée.
-- ===========================================================================
-- (contexte = 651-B) tenter d'écrire un acte avec cabinet_id = 651-A
SELECT throws_ok(
  $$ INSERT INTO consultation_act
       (cabinet_id, appointment_id, patient_id, practitioner_id,
        ccam_code, label, amount_cents)
     VALUES (
       '65100000-0000-0000-0000-000000000001',
       '65100000-0000-0000-0000-0000000000d1',
       '65100000-0000-0000-0000-0000000000b1',
       '65100000-0000-0000-0000-0000000000c1',
       'HBLD099', 'Pirate cross-tenant', 0
     ) $$,
  '42501', NULL,
  '⭐ WITH CHECK : insertion consultation_act cross-tenant refusée');

-- ===========================================================================
-- 5. APPOINTMENT COMPLETION : started_at / completed_at scoped au tenant.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '65100000-0000-0000-0000-000000000001';
UPDATE appointment
  SET started_at = '2025-06-01 09:05:00+00'
  WHERE id = '65100000-0000-0000-0000-0000000000d1';

SELECT is(
  (SELECT started_at FROM appointment
   WHERE  id = '65100000-0000-0000-0000-0000000000d1'),
  '2025-06-01 09:05:00+00'::timestamptz,
  'appointment.started_at mis à jour et visible dans le bon tenant');

-- Depuis 651-B, l'appointment de 651-A est invisible (complétion tenant-scoped)
SET LOCAL app.current_cabinet_id = '65100000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*) FROM appointment
   WHERE id = '65100000-0000-0000-0000-0000000000d1')::int, 0,
  '⭐ appointment completion scoped : appointment 651-A invisible depuis 651-B');

SELECT * FROM finish();
ROLLBACK;
