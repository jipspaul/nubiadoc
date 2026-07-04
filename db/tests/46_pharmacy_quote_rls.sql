-- 46_pharmacy_quote_rls.sql — Contrat RLS pharmacy_quote (issue #3312, lot B7).
-- Vérifie : fail-closed · isolation cross-pharmacie · le patient ne voit
-- jamais un brouillon · WITH CHECK (la pharmacie ne forge pas la décision,
-- le patient ne modifie qu'un devis envoyé) · pas de DELETE.
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK. Préfixe 33120000.

BEGIN;
SELECT * FROM no_plan();

-- Fixtures : compte patient + pharmacie X + devis draft et devis sent.
INSERT INTO app_user (id, email, kind, status)
  VALUES ('33120000-0000-0000-0000-0000000000a1', 'patient-b7@demo-3312.test', 'patient', 'active')
  ON CONFLICT DO NOTHING;
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('33120000-0000-0000-0000-0000000000b1', '33120000-0000-0000-0000-0000000000a1', 'Jean', 'Demo')
  ON CONFLICT DO NOTHING;
SET LOCAL app.current_pharmacy_id = '33120000-0000-0000-0000-0000000000f1';
INSERT INTO pharmacy (id, raison_sociale, is_listed)
  VALUES ('33120000-0000-0000-0000-0000000000f1', 'Pharmacie B7-X', true)
  ON CONFLICT DO NOTHING;
INSERT INTO pharmacy_quote (id, pharmacy_id, patient_account_id, pharmacy_name,
                            patient_display_name, items, total_cents, status)
  VALUES ('33120000-0000-0000-0000-000000000051', '33120000-0000-0000-0000-0000000000f1',
          '33120000-0000-0000-0000-0000000000b1', 'Pharmacie B7-X', 'Jean D.',
          '[{"label": "Bain de bouche", "qty": 1, "unit_price_cents": 650}]', 650, 'draft')
  ON CONFLICT DO NOTHING;
INSERT INTO pharmacy_quote (id, pharmacy_id, patient_account_id, pharmacy_name,
                            patient_display_name, items, total_cents, status, sent_at)
  VALUES ('33120000-0000-0000-0000-000000000052', '33120000-0000-0000-0000-0000000000f1',
          '33120000-0000-0000-0000-0000000000b1', 'Pharmacie B7-X', 'Jean D.',
          '[{"label": "Brossettes", "qty": 2, "unit_price_cents": 300}]', 600, 'sent', now())
  ON CONFLICT DO NOTHING;
RESET app.current_pharmacy_id;

-- 1. Fail-closed sans GUC.
SELECT is(
  (SELECT count(*)::int FROM pharmacy_quote
   WHERE id IN ('33120000-0000-0000-0000-000000000051','33120000-0000-0000-0000-000000000052')),
  0, '⭐ fail-closed : devis invisibles sans GUC');

-- 2. La pharmacie voit ses deux devis ; une autre pharmacie rien.
SET LOCAL app.current_pharmacy_id = '33120000-0000-0000-0000-0000000000f1';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_quote
   WHERE id IN ('33120000-0000-0000-0000-000000000051','33120000-0000-0000-0000-000000000052')),
  2, 'pharmacie X : voit brouillon et envoyé');
SET LOCAL app.current_pharmacy_id = '33120000-0000-0000-0000-0000000000f2';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_quote
   WHERE id IN ('33120000-0000-0000-0000-000000000051','33120000-0000-0000-0000-000000000052')),
  0, '⭐ non-fuite : autre pharmacie ne voit rien');
RESET app.current_pharmacy_id;

-- 3. Le patient ne voit JAMAIS un brouillon, seulement les devis envoyés.
SET LOCAL app.patient_account_id = '33120000-0000-0000-0000-0000000000b1';
SELECT is(
  (SELECT count(*)::int FROM pharmacy_quote WHERE id = '33120000-0000-0000-0000-000000000051'),
  0, '⭐ le patient ne voit pas un brouillon');
SELECT is(
  (SELECT count(*)::int FROM pharmacy_quote WHERE id = '33120000-0000-0000-0000-000000000052'),
  1, 'le patient voit le devis envoyé');

-- 4. Le patient décide (sent → accepted) mais ne peut pas revenir dessus.
UPDATE pharmacy_quote SET status = 'accepted', decided_at = now()
  WHERE id = '33120000-0000-0000-0000-000000000052';
SELECT is(
  (SELECT status FROM pharmacy_quote WHERE id = '33120000-0000-0000-0000-000000000052'),
  'accepted', 'le patient accepte un devis envoyé');
-- Re-décision : la policy USING (status = sent) ne matche plus → 0 ligne.
UPDATE pharmacy_quote SET status = 'refused'
  WHERE id = '33120000-0000-0000-0000-000000000052';
SELECT is(
  (SELECT status FROM pharmacy_quote WHERE id = '33120000-0000-0000-0000-000000000052'),
  'accepted', '⭐ une décision est définitive côté patient (0 ligne modifiée)');
RESET app.patient_account_id;

-- 5. WITH CHECK : la pharmacie ne peut pas forger la décision du patient.
SET LOCAL app.current_pharmacy_id = '33120000-0000-0000-0000-0000000000f1';
SELECT throws_ok(
  $$ UPDATE pharmacy_quote SET status = 'accepted'
     WHERE id = '33120000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ WITH CHECK : la pharmacie ne peut pas accepter à la place du patient');

-- 6. Pas de DELETE pour nubia_app.
SELECT throws_ok(
  $$ DELETE FROM pharmacy_quote WHERE id = '33120000-0000-0000-0000-000000000051' $$,
  '42501', NULL,
  '⭐ pas de DELETE sur pharmacy_quote pour nubia_app');
RESET app.current_pharmacy_id;

SELECT * FROM finish();
ROLLBACK;
