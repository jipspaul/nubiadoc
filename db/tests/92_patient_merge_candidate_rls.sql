-- 92_patient_merge_candidate_rls.sql — patient_merge_candidate (#3916, lot
-- interop A5). Vérifie : fail-closed · isolation cross-cabinet · WITH CHECK
-- anti-forgerie · CHECK reason/status · le trigger de flagging automatique
-- (même ins_bidx -> flag 'same_ins' ; ins_bidx identique + démographie
-- divergente -> 'ins_and_demographics_diverge').
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK. Préfixe 92000000.

BEGIN;
SELECT * FROM no_plan();

-- Fixtures : cabinet A (propriétaire) et cabinet B (témoin cross-tenant).
SET LOCAL app.current_cabinet_id = '92000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('92000000-0000-0000-0000-000000000001', 'Cabinet A5-A')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '92000000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('92000000-0000-0000-0000-000000000002', 'Cabinet A5-B')
  ON CONFLICT DO NOTHING;
RESET app.current_cabinet_id;

-- ===========================================================================
-- 1. Flagging automatique : même ins_bidx, même démographie -> 'same_ins'.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '92000000-0000-0000-0000-000000000001';

INSERT INTO patient (id, cabinet_id, first_name, last_name, birth_date, ins_bidx)
  VALUES ('92000000-0000-0000-0000-0000000000a1',
          '92000000-0000-0000-0000-000000000001',
          'Alice', 'Martin', '1990-01-01', 'bidx-same-1');

INSERT INTO patient (id, cabinet_id, first_name, last_name, birth_date, ins_bidx)
  VALUES ('92000000-0000-0000-0000-0000000000a2',
          '92000000-0000-0000-0000-000000000001',
          'Alice', 'Martin', '1990-01-01', 'bidx-same-1');

SELECT is(
  (SELECT reason::text FROM patient_merge_candidate
     WHERE patient_a_id = '92000000-0000-0000-0000-0000000000a1'
       AND patient_b_id = '92000000-0000-0000-0000-0000000000a2'),
  'same_ins',
  'trigger : même ins_bidx + démographie identique -> flag same_ins');

-- ===========================================================================
-- 2. Même ins_bidx, démographie divergente -> 'ins_and_demographics_diverge'.
-- ===========================================================================
INSERT INTO patient (id, cabinet_id, first_name, last_name, birth_date, ins_bidx)
  VALUES ('92000000-0000-0000-0000-0000000000b1',
          '92000000-0000-0000-0000-000000000001',
          'Bruno', 'Dupont', '1985-05-05', 'bidx-diverge-1');

INSERT INTO patient (id, cabinet_id, first_name, last_name, birth_date, ins_bidx)
  VALUES ('92000000-0000-0000-0000-0000000000b2',
          '92000000-0000-0000-0000-000000000001',
          'Bruno', 'Dupont-Typo', '1985-05-06', 'bidx-diverge-1');

SELECT is(
  (SELECT reason::text FROM patient_merge_candidate
     WHERE patient_a_id = '92000000-0000-0000-0000-0000000000b1'
       AND patient_b_id = '92000000-0000-0000-0000-0000000000b2'),
  'ins_and_demographics_diverge',
  'trigger : même ins_bidx + démographie divergente -> flag ins_and_demographics_diverge');

-- ===========================================================================
-- 3. Pas de doublon d'ins_bidx -> aucun flag.
-- ===========================================================================
INSERT INTO patient (id, cabinet_id, first_name, last_name, birth_date, ins_bidx)
  VALUES ('92000000-0000-0000-0000-0000000000c1',
          '92000000-0000-0000-0000-000000000001',
          'Claire', 'Petit', '1970-03-03', 'bidx-unique-1');

SELECT is(
  (SELECT count(*)::int FROM patient_merge_candidate
     WHERE patient_a_id = '92000000-0000-0000-0000-0000000000c1'
        OR patient_b_id = '92000000-0000-0000-0000-0000000000c1'),
  0,
  'trigger : ins_bidx sans doublon -> aucun candidat flagué');

RESET app.current_cabinet_id;

-- ===========================================================================
-- 4. FAIL-CLOSED : sans GUC -> aucun candidat visible.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM patient_merge_candidate),
  0,
  '⭐ fail-closed : aucun patient_merge_candidate visible sans app.current_cabinet_id');

-- ===========================================================================
-- 5. Isolation cross-cabinet.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '92000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM patient_merge_candidate),
  2,
  'cabinet propriétaire : voit ses 2 candidats flagués');
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '92000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM patient_merge_candidate),
  0,
  '⭐ non-fuite : un autre cabinet ne voit aucun candidat du cabinet A');
RESET app.current_cabinet_id;

-- ===========================================================================
-- 6. WITH CHECK : impossible de forger un candidat pour un autre cabinet.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '92000000-0000-0000-0000-000000000002';
SELECT throws_ok(
  $$ INSERT INTO patient_merge_candidate (cabinet_id, patient_a_id, patient_b_id, reason)
     VALUES ('92000000-0000-0000-0000-000000000001',
             '92000000-0000-0000-0000-0000000000a1',
             '92000000-0000-0000-0000-0000000000a2',
             'same_ins') $$,
  '42501', NULL,
  '⭐ WITH CHECK : impossible de forger un candidat pour un autre cabinet');
RESET app.current_cabinet_id;

-- ===========================================================================
-- 7. CHECK reason/status : valeurs hors énum rejetées.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '92000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$ INSERT INTO patient_merge_candidate (cabinet_id, patient_a_id, patient_b_id, reason)
     VALUES ('92000000-0000-0000-0000-000000000001',
             '92000000-0000-0000-0000-0000000000c1',
             '92000000-0000-0000-0000-0000000000b1',
             'bogus_reason') $$,
  '23514', NULL,
  '⭐ CHECK : reason invalide rejetée');
RESET app.current_cabinet_id;

SELECT * FROM finish();
ROLLBACK;
