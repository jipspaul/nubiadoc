-- 29_waiting_list.sql — RLS + unicité de waiting_list_entry.
-- Vérifie : structure, tenant_isolation (fail-closed + non-fuite), contrainte
-- anti-doublon (patient actif même provider → erreur 23505).
-- Issue #1670 — POST /v1/waiting-list.
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures  (préfixe UUID : e7380000-…)
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'e7380000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('e7380000-0000-0000-0000-000000000001', 'Cabinet WL-A');

-- Provider rattaché à cabinet A (annuaire public)
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('e7380000-0000-0000-0000-0000000000a1', 'prov.wl@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed)
  VALUES ('e7380000-0000-0000-0000-0000000000b1',
          'e7380000-0000-0000-0000-000000000001',
          'e7380000-0000-0000-0000-0000000000a1',
          'Dr WL', true, true);

-- Patient dans cabinet A
INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('e7380000-0000-0000-0000-0000000000d1',
          'e7380000-0000-0000-0000-000000000001', 'Willy', 'List');

-- Cabinet B + patient B
SET LOCAL app.current_cabinet_id = 'e7380000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('e7380000-0000-0000-0000-000000000002', 'Cabinet WL-B');
INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('e7380000-0000-0000-0000-0000000000d2',
          'e7380000-0000-0000-0000-000000000002', 'Wendy', 'B');

-- ===========================================================================
-- 1. Structure : colonnes attendues présentes.
-- ===========================================================================
SELECT has_column('waiting_list_entry', 'id',             '⭐ waiting_list_entry.id présent');
SELECT has_column('waiting_list_entry', 'cabinet_id',     '⭐ waiting_list_entry.cabinet_id présent');
SELECT has_column('waiting_list_entry', 'patient_id',     '⭐ waiting_list_entry.patient_id présent');
SELECT has_column('waiting_list_entry', 'provider_id',    '⭐ waiting_list_entry.provider_id présent (0082)');
SELECT has_column('waiting_list_entry', 'desired_window', '⭐ waiting_list_entry.desired_window présent');
SELECT has_column('waiting_list_entry', 'status',         '⭐ waiting_list_entry.status présent');

-- ===========================================================================
-- 2. Happy path : inscription active insérée avec succès.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'e7380000-0000-0000-0000-000000000001';
INSERT INTO waiting_list_entry (id, cabinet_id, patient_id, provider_id, desired_window)
  VALUES ('e7380000-0000-0000-0000-0000000000e1',
          'e7380000-0000-0000-0000-000000000001',
          'e7380000-0000-0000-0000-0000000000d1',
          'e7380000-0000-0000-0000-0000000000b1',
          '{"motif":"bilan"}');

SELECT is(
  (SELECT status FROM waiting_list_entry
   WHERE id = 'e7380000-0000-0000-0000-0000000000e1'),
  'active',
  '⭐ happy path : entrée créée avec status=active');

-- ===========================================================================
-- 3. 409 — doublon actif même patient + même provider → UNIQUE violation.
-- ===========================================================================
SELECT throws_ok(
  $$INSERT INTO waiting_list_entry
      (cabinet_id, patient_id, provider_id, desired_window)
    VALUES
      ('e7380000-0000-0000-0000-000000000001',
       'e7380000-0000-0000-0000-0000000000d1',
       'e7380000-0000-0000-0000-0000000000b1',
       '{"motif":"controle"}')$$,
  '23505', NULL,
  '⭐ 409 anti-doublon : second INSERT actif même patient+provider refusé (UNIQUE violation)');

-- Un patient annulé peut se réinscrire (la contrainte est partielle sur status=active).
UPDATE waiting_list_entry
  SET status = 'cancelled'
  WHERE id = 'e7380000-0000-0000-0000-0000000000e1';

INSERT INTO waiting_list_entry (cabinet_id, patient_id, provider_id, desired_window)
  VALUES ('e7380000-0000-0000-0000-000000000001',
          'e7380000-0000-0000-0000-0000000000d1',
          'e7380000-0000-0000-0000-0000000000b1',
          '{"motif":"nouvelle demande"}');

SELECT is(
  (SELECT count(*)::int FROM waiting_list_entry
   WHERE patient_id = 'e7380000-0000-0000-0000-0000000000d1' AND status = 'active'),
  1,
  '⭐ réinscription OK après annulation (contrainte partielle active uniquement)');

-- ===========================================================================
-- 4. RLS — fail-closed : sans GUC positionné → aucune entrée visible.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM waiting_list_entry
   WHERE cabinet_id IN (
     'e7380000-0000-0000-0000-000000000001',
     'e7380000-0000-0000-0000-000000000002')),
  0,
  '⭐ fail-closed : waiting_list_entry invisible sans app.current_cabinet_id');

-- ===========================================================================
-- 5. RLS — isolation inter-cabinet : contexte A ne voit pas B.
-- ===========================================================================
-- Entrée dans cabinet B insérée sous contexte B
SET LOCAL app.current_cabinet_id = 'e7380000-0000-0000-0000-000000000002';
INSERT INTO waiting_list_entry (cabinet_id, patient_id, desired_window)
  VALUES ('e7380000-0000-0000-0000-000000000002',
          'e7380000-0000-0000-0000-0000000000d2',
          '{}');

-- Depuis contexte A : aucune entrée de B visible.
SET LOCAL app.current_cabinet_id = 'e7380000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM waiting_list_entry
   WHERE cabinet_id = 'e7380000-0000-0000-0000-000000000002'),
  0,
  '⭐ non-fuite : contexte A ne voit AUCUNE entrée de B');

-- ===========================================================================
-- 6. RLS WITH CHECK — écriture cross-tenant refusée.
-- ===========================================================================
SELECT throws_ok(
  $$INSERT INTO waiting_list_entry (cabinet_id, patient_id, desired_window)
    VALUES ('e7380000-0000-0000-0000-000000000002',
            'e7380000-0000-0000-0000-0000000000d2', '{}')$$,
  '42501', NULL,
  '⭐ WITH CHECK : écriture dans un autre cabinet refusée depuis contexte A');

SELECT * FROM finish();
ROLLBACK;
