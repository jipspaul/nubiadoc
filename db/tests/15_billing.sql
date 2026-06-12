-- 15_billing.sql — pgTAP integration tests for billing schema (issue #760).
-- Tables : quote, quote_item, signature, payment_schedule, payment.
-- Vérifie : existence, colonnes, FK, contraintes CHECK, RLS fail-closed,
--           isolation cross-tenant, immutabilité du devis signé (0051).
-- Tourne sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- 1. Existence des tables
-- ===========================================================================
SELECT has_table('quote',            'table quote présente');
SELECT has_table('quote_item',       'table quote_item présente');
SELECT has_table('signature',        'table signature présente');
SELECT has_table('payment_schedule', 'table payment_schedule présente');
SELECT has_table('payment',          'table payment présente');

-- ===========================================================================
-- 2. Colonnes & types clés
-- ===========================================================================

-- quote
SELECT has_column('quote', 'cabinet_id',    'quote.cabinet_id présent (tenant)');
SELECT col_not_null('quote', 'cabinet_id',  'quote.cabinet_id NOT NULL');
SELECT col_type_is('quote', 'cabinet_id', 'uuid', 'quote.cabinet_id uuid');
SELECT has_column('quote', 'patient_id',    'quote.patient_id présent');
SELECT col_not_null('quote', 'patient_id',  'quote.patient_id NOT NULL');
SELECT has_column('quote', 'status',        'quote.status présent');
SELECT col_not_null('quote', 'status',      'quote.status NOT NULL');
SELECT col_has_default('quote', 'status',   'quote.status a un défaut (draft)');
SELECT has_column('quote', 'total_amount',  'quote.total_amount présent');
SELECT col_type_is('quote', 'total_amount', 'numeric(12,2)', 'quote.total_amount numeric(12,2) — pas de float');
SELECT col_not_null('quote', 'total_amount','quote.total_amount NOT NULL');
SELECT has_column('quote', 'currency',      'quote.currency présent');
SELECT col_type_is('quote', 'currency', 'character(3)', 'quote.currency char(3)');
SELECT col_not_null('quote', 'currency',    'quote.currency NOT NULL');
SELECT has_column('quote', 'signed_at',     'quote.signed_at présent (horodatage signature)');
SELECT has_column('quote', 'signed_sha256', 'quote.signed_sha256 présent (empreinte PDF)');
SELECT has_column('quote', 'signature_id',  'quote.signature_id présent (FK optionnelle)');
SELECT has_column('quote', 'created_at',    'quote.created_at présent');
SELECT has_column('quote', 'deleted_at',    'quote.deleted_at présent (soft-delete)');
SELECT has_column('quote', 'deposit_paid',  'quote.deposit_paid présent (0093)');
SELECT col_not_null('quote', 'deposit_paid','quote.deposit_paid NOT NULL');
SELECT has_column('quote', 'deposit_pct',   'quote.deposit_pct présent (0094)');
SELECT col_type_is('quote', 'deposit_pct', 'numeric(5,2)', 'quote.deposit_pct numeric(5,2)');

-- quote_item
SELECT has_column('quote_item', 'cabinet_id',    'quote_item.cabinet_id présent (tenant)');
SELECT col_not_null('quote_item', 'cabinet_id',  'quote_item.cabinet_id NOT NULL');
SELECT has_column('quote_item', 'quote_id',      'quote_item.quote_id présent');
SELECT col_not_null('quote_item', 'quote_id',    'quote_item.quote_id NOT NULL');
SELECT has_column('quote_item', 'label',         'quote_item.label présent');
SELECT col_not_null('quote_item', 'label',       'quote_item.label NOT NULL');
SELECT has_column('quote_item', 'unit_amount',   'quote_item.unit_amount présent');
SELECT col_type_is('quote_item', 'unit_amount', 'numeric(12,2)', 'quote_item.unit_amount numeric(12,2)');

-- signature
SELECT has_column('signature', 'cabinet_id',    'signature.cabinet_id présent (tenant)');
SELECT col_not_null('signature', 'cabinet_id',  'signature.cabinet_id NOT NULL');
SELECT has_column('signature', 'provider',      'signature.provider présent');
SELECT col_not_null('signature', 'provider',    'signature.provider NOT NULL');
SELECT has_column('signature', 'provider_ref',  'signature.provider_ref présent');
SELECT col_not_null('signature', 'provider_ref','signature.provider_ref NOT NULL');
SELECT has_column('signature', 'level',         'signature.level présent (eIDAS)');
SELECT col_not_null('signature', 'level',       'signature.level NOT NULL');

-- payment
SELECT has_column('payment', 'cabinet_id',   'payment.cabinet_id présent (tenant)');
SELECT col_not_null('payment', 'cabinet_id', 'payment.cabinet_id NOT NULL');
SELECT has_column('payment', 'amount',       'payment.amount présent');
SELECT col_type_is('payment', 'amount', 'numeric(12,2)', 'payment.amount numeric(12,2) — pas de float');
SELECT col_not_null('payment', 'amount',     'payment.amount NOT NULL');
SELECT has_column('payment', 'kind',         'payment.kind présent');
SELECT col_not_null('payment', 'kind',       'payment.kind NOT NULL');
SELECT has_column('payment', 'status',       'payment.status présent');
SELECT col_not_null('payment', 'status',     'payment.status NOT NULL');
SELECT has_column('payment', 'provider',     'payment.provider présent');
SELECT col_not_null('payment', 'provider',   'payment.provider NOT NULL');

-- payment_schedule
SELECT has_column('payment_schedule', 'cabinet_id',    'payment_schedule.cabinet_id présent (tenant)');
SELECT col_not_null('payment_schedule', 'cabinet_id',  'payment_schedule.cabinet_id NOT NULL');
SELECT has_column('payment_schedule', 'total_amount',  'payment_schedule.total_amount présent');
SELECT col_not_null('payment_schedule', 'total_amount','payment_schedule.total_amount NOT NULL');

-- ===========================================================================
-- 3. Clés étrangères (catalogue — pas de données nécessaires)
-- ===========================================================================
SELECT fk_ok('quote',            'cabinet_id',  'cabinet',          'id');
SELECT fk_ok('quote',            'patient_id',  'patient',          'id');
SELECT fk_ok('quote',            'signature_id','signature',         'id');
SELECT fk_ok('quote_item',       'cabinet_id',  'cabinet',          'id');
SELECT fk_ok('quote_item',       'quote_id',    'quote',            'id');
SELECT fk_ok('signature',        'cabinet_id',  'cabinet',          'id');
SELECT fk_ok('payment_schedule', 'cabinet_id',  'cabinet',          'id');
SELECT fk_ok('payment_schedule', 'patient_id',  'patient',          'id');
SELECT fk_ok('payment_schedule', 'quote_id',    'quote',            'id');
SELECT fk_ok('payment',          'cabinet_id',  'cabinet',          'id');
SELECT fk_ok('payment',          'patient_id',  'patient',          'id');
SELECT fk_ok('payment',          'schedule_id', 'payment_schedule', 'id');
SELECT fk_ok('payment',          'quote_id',    'quote',            'id');

-- ===========================================================================
-- 4. RLS : ENABLE + FORCE + policy tenant_isolation (catalogue)
-- ===========================================================================
SELECT ok( (SELECT relrowsecurity     FROM pg_class WHERE relname = 'quote'),
  'quote : ROW LEVEL SECURITY activée (0011)');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'quote'),
  'quote : FORCE ROW LEVEL SECURITY (0011)');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'quote' AND policyname = 'tenant_isolation'),
  'quote : policy tenant_isolation présente (0011)');

SELECT ok( (SELECT relrowsecurity     FROM pg_class WHERE relname = 'quote_item'),
  'quote_item : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'quote_item'),
  'quote_item : FORCE ROW LEVEL SECURITY');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'quote_item' AND policyname = 'tenant_isolation'),
  'quote_item : policy tenant_isolation présente');

SELECT ok( (SELECT relrowsecurity     FROM pg_class WHERE relname = 'signature'),
  'signature : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'signature'),
  'signature : FORCE ROW LEVEL SECURITY');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'signature' AND policyname = 'tenant_isolation'),
  'signature : policy tenant_isolation présente');

SELECT ok( (SELECT relrowsecurity     FROM pg_class WHERE relname = 'payment_schedule'),
  'payment_schedule : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'payment_schedule'),
  'payment_schedule : FORCE ROW LEVEL SECURITY');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'payment_schedule' AND policyname = 'tenant_isolation'),
  'payment_schedule : policy tenant_isolation présente');

SELECT ok( (SELECT relrowsecurity     FROM pg_class WHERE relname = 'payment'),
  'payment : ROW LEVEL SECURITY activée');
SELECT ok( (SELECT relforcerowsecurity FROM pg_class WHERE relname = 'payment'),
  'payment : FORCE ROW LEVEL SECURITY');
SELECT ok( EXISTS(SELECT 1 FROM pg_policies WHERE tablename = 'payment' AND policyname = 'tenant_isolation'),
  'payment : policy tenant_isolation présente');

-- Trigger d'immutabilité (0051)
SELECT ok(
  EXISTS(SELECT 1 FROM pg_trigger t
         JOIN pg_class c ON c.oid = t.tgrelid
         WHERE c.relname = 'quote' AND t.tgname = 'quote_signed_immutable'),
  'quote : trigger quote_signed_immutable présent (0051)');

-- ===========================================================================
-- 5. Fixtures : cabinet A + cabinet B pour les tests suivants
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('f0000000-0000-0000-0000-000000000001', 'Cabinet Billing A');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('f0000000-0000-0000-0000-0000000000d1', 'f0000000-0000-0000-0000-000000000001', 'Alice', 'Billing');

-- Cabinet B
SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('f0000000-0000-0000-0000-000000000002', 'Cabinet Billing B');
INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES
  ('f0000000-0000-0000-0000-0000000000d2', 'f0000000-0000-0000-0000-000000000002', 'Bob', 'Billing');

-- ===========================================================================
-- 6. CHECK constraints
-- ===========================================================================
SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';

-- quote.status : valeur invalide
SELECT throws_ok(
  $$ INSERT INTO quote (cabinet_id, patient_id, status)
     VALUES ('f0000000-0000-0000-0000-000000000001',
             'f0000000-0000-0000-0000-0000000000d1',
             'invalid_status') $$,
  '23514', NULL,
  'quote.status invalide rejeté (CHECK)');

-- quote.deposit_pct : valeur hors domaine
SELECT throws_ok(
  $$ INSERT INTO quote (cabinet_id, patient_id, deposit_pct)
     VALUES ('f0000000-0000-0000-0000-000000000001',
             'f0000000-0000-0000-0000-0000000000d1',
             150.00) $$,
  '23514', NULL,
  'quote.deposit_pct > 100 rejeté (CHECK 0094)');

SELECT throws_ok(
  $$ INSERT INTO quote (cabinet_id, patient_id, deposit_pct)
     VALUES ('f0000000-0000-0000-0000-000000000001',
             'f0000000-0000-0000-0000-0000000000d1',
             -1.00) $$,
  '23514', NULL,
  'quote.deposit_pct < 0 rejeté (CHECK 0094)');

-- Quotes valides pour les tests suivants
INSERT INTO quote (id, cabinet_id, patient_id) VALUES
  ('f0000000-0000-0000-0000-000000000011',
   'f0000000-0000-0000-0000-000000000001',
   'f0000000-0000-0000-0000-0000000000d1');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000002';
INSERT INTO quote (id, cabinet_id, patient_id) VALUES
  ('f0000000-0000-0000-0000-000000000012',
   'f0000000-0000-0000-0000-000000000002',
   'f0000000-0000-0000-0000-0000000000d2');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';

-- payment.kind : valeur invalide
SELECT throws_ok(
  $$ INSERT INTO payment (cabinet_id, patient_id, amount, kind, provider, status)
     VALUES ('f0000000-0000-0000-0000-000000000001',
             'f0000000-0000-0000-0000-0000000000d1',
             100.00, 'bad_kind', 'stripe', 'pending') $$,
  '23514', NULL,
  'payment.kind invalide rejeté (CHECK)');

-- payment.status : valeur invalide
SELECT throws_ok(
  $$ INSERT INTO payment (cabinet_id, patient_id, amount, kind, provider, status)
     VALUES ('f0000000-0000-0000-0000-000000000001',
             'f0000000-0000-0000-0000-0000000000d1',
             100.00, 'full', 'stripe', 'bad_status') $$,
  '23514', NULL,
  'payment.status invalide rejeté (CHECK)');

-- payment_schedule.status : valeur invalide
SELECT throws_ok(
  $$ INSERT INTO payment_schedule (cabinet_id, patient_id, total_amount, status)
     VALUES ('f0000000-0000-0000-0000-000000000001',
             'f0000000-0000-0000-0000-0000000000d1',
             500.00, 'bad_status') $$,
  '23514', NULL,
  'payment_schedule.status invalide rejeté (CHECK)');

-- ===========================================================================
-- 7. RLS ISOLATION cross-tenant (quote, quote_item, signature, payment_schedule, payment)
-- ===========================================================================

-- --- quote ---
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*) FROM quote
   WHERE id IN ('f0000000-0000-0000-0000-000000000011',
                'f0000000-0000-0000-0000-000000000012'))::int, 0,
  '⭐ fail-closed quote : aucun devis visible sans app.current_cabinet_id');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM quote
   WHERE id IN ('f0000000-0000-0000-0000-000000000011',
                'f0000000-0000-0000-0000-000000000012'))::int, 1,
  'quote contexte A : 1 devis visible (le sien)');
SELECT is(
  (SELECT count(*) FROM quote WHERE id = 'f0000000-0000-0000-0000-000000000012')::int, 0,
  '⭐ non-fuite quote : cabinet A ne voit PAS les devis de B');

SELECT throws_ok(
  $$ INSERT INTO quote (cabinet_id, patient_id)
     VALUES ('f0000000-0000-0000-0000-000000000002',
             'f0000000-0000-0000-0000-0000000000d1') $$,
  '42501', NULL,
  '⭐ WITH CHECK quote : écriture cross-tenant refusée (42501)');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*) FROM quote
   WHERE id IN ('f0000000-0000-0000-0000-000000000011',
                'f0000000-0000-0000-0000-000000000012'))::int, 1,
  'quote contexte B : 1 devis visible (le sien)');
SELECT is(
  (SELECT count(*) FROM quote WHERE id = 'f0000000-0000-0000-0000-000000000011')::int, 0,
  '⭐ non-fuite quote : cabinet B ne voit PAS les devis de A');

-- --- quote_item ---
SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
INSERT INTO quote_item (id, cabinet_id, quote_id, label, unit_amount) VALUES
  ('f0000000-0000-0000-0000-000000000040',
   'f0000000-0000-0000-0000-000000000001',
   'f0000000-0000-0000-0000-000000000011',
   'Soin dentaire A', 150.00);

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000002';
INSERT INTO quote_item (id, cabinet_id, quote_id, label, unit_amount) VALUES
  ('f0000000-0000-0000-0000-000000000041',
   'f0000000-0000-0000-0000-000000000002',
   'f0000000-0000-0000-0000-000000000012',
   'Soin dentaire B', 200.00);

RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*) FROM quote_item
   WHERE id IN ('f0000000-0000-0000-0000-000000000040',
                'f0000000-0000-0000-0000-000000000041'))::int, 0,
  '⭐ fail-closed quote_item : aucun item visible sans GUC');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM quote_item
   WHERE id IN ('f0000000-0000-0000-0000-000000000040',
                'f0000000-0000-0000-0000-000000000041'))::int, 1,
  'quote_item contexte A : 1 item visible (le sien)');
SELECT is(
  (SELECT count(*) FROM quote_item WHERE id = 'f0000000-0000-0000-0000-000000000041')::int, 0,
  '⭐ non-fuite quote_item : cabinet A ne voit PAS les items de B');

-- --- signature ---
SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
INSERT INTO signature (id, cabinet_id, provider, provider_ref) VALUES
  ('f0000000-0000-0000-0000-000000000050',
   'f0000000-0000-0000-0000-000000000001',
   'yousign', 'ys-ref-a');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000002';
INSERT INTO signature (id, cabinet_id, provider, provider_ref) VALUES
  ('f0000000-0000-0000-0000-000000000051',
   'f0000000-0000-0000-0000-000000000002',
   'yousign', 'ys-ref-b');

RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*) FROM signature
   WHERE id IN ('f0000000-0000-0000-0000-000000000050',
                'f0000000-0000-0000-0000-000000000051'))::int, 0,
  '⭐ fail-closed signature : aucune signature visible sans GUC');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM signature
   WHERE id IN ('f0000000-0000-0000-0000-000000000050',
                'f0000000-0000-0000-0000-000000000051'))::int, 1,
  'signature contexte A : 1 signature visible (la sienne)');
SELECT is(
  (SELECT count(*) FROM signature WHERE id = 'f0000000-0000-0000-0000-000000000051')::int, 0,
  '⭐ non-fuite signature : cabinet A ne voit PAS les signatures de B');

-- --- payment_schedule ---
SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
INSERT INTO payment_schedule (id, cabinet_id, patient_id, total_amount) VALUES
  ('f0000000-0000-0000-0000-000000000060',
   'f0000000-0000-0000-0000-000000000001',
   'f0000000-0000-0000-0000-0000000000d1',
   1200.00);

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000002';
INSERT INTO payment_schedule (id, cabinet_id, patient_id, total_amount) VALUES
  ('f0000000-0000-0000-0000-000000000061',
   'f0000000-0000-0000-0000-000000000002',
   'f0000000-0000-0000-0000-0000000000d2',
   2400.00);

RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*) FROM payment_schedule
   WHERE id IN ('f0000000-0000-0000-0000-000000000060',
                'f0000000-0000-0000-0000-000000000061'))::int, 0,
  '⭐ fail-closed payment_schedule : aucun échéancier visible sans GUC');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM payment_schedule
   WHERE id IN ('f0000000-0000-0000-0000-000000000060',
                'f0000000-0000-0000-0000-000000000061'))::int, 1,
  'payment_schedule contexte A : 1 échéancier visible (le sien)');
SELECT is(
  (SELECT count(*) FROM payment_schedule WHERE id = 'f0000000-0000-0000-0000-000000000061')::int, 0,
  '⭐ non-fuite payment_schedule : cabinet A ne voit PAS l''échéancier de B');

-- --- payment ---
SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
INSERT INTO payment (id, cabinet_id, patient_id, amount, kind, provider, status) VALUES
  ('f0000000-0000-0000-0000-000000000070',
   'f0000000-0000-0000-0000-000000000001',
   'f0000000-0000-0000-0000-0000000000d1',
   300.00, 'deposit', 'stripe', 'paid');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000002';
INSERT INTO payment (id, cabinet_id, patient_id, amount, kind, provider, status) VALUES
  ('f0000000-0000-0000-0000-000000000071',
   'f0000000-0000-0000-0000-000000000002',
   'f0000000-0000-0000-0000-0000000000d2',
   600.00, 'full', 'gocardless', 'pending');

RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*) FROM payment
   WHERE id IN ('f0000000-0000-0000-0000-000000000070',
                'f0000000-0000-0000-0000-000000000071'))::int, 0,
  '⭐ fail-closed payment : aucun paiement visible sans GUC');

SET LOCAL app.current_cabinet_id = 'f0000000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*) FROM payment
   WHERE id IN ('f0000000-0000-0000-0000-000000000070',
                'f0000000-0000-0000-0000-000000000071'))::int, 1,
  'payment contexte A : 1 paiement visible (le sien)');
SELECT is(
  (SELECT count(*) FROM payment WHERE id = 'f0000000-0000-0000-0000-000000000071')::int, 0,
  '⭐ non-fuite payment : cabinet A ne voit PAS les paiements de B');

SELECT throws_ok(
  $$ INSERT INTO payment (cabinet_id, patient_id, amount, kind, provider, status)
     VALUES ('f0000000-0000-0000-0000-000000000002',
             'f0000000-0000-0000-0000-0000000000d1',
             100.00, 'full', 'stripe', 'paid') $$,
  '42501', NULL,
  '⭐ WITH CHECK payment : écriture cross-tenant refusée (42501)');

-- ===========================================================================
-- 8. Quote immuable après signature (trigger enforce_quote_immutable, 0051)
-- ===========================================================================
-- Contexte : toujours cabinet A
-- D'abord : devis non signé → UPDATE autorisé
SELECT lives_ok(
  $$ UPDATE quote SET total_amount = 250.00
     WHERE id = 'f0000000-0000-0000-0000-000000000011' $$,
  'quote non signée (draft) : UPDATE autorisé (trigger ne bloque pas)');

-- Signer le devis (transition draft → signed : trigger autorise)
UPDATE quote SET status = 'signed', signed_at = now()
  WHERE id = 'f0000000-0000-0000-0000-000000000011';

-- Après signature : tout UPDATE est bloqué (P0001)
SELECT throws_ok(
  $$ UPDATE quote SET total_amount = 9999.99
     WHERE id = 'f0000000-0000-0000-0000-000000000011' $$,
  'P0001', NULL,
  '⭐ quote signée immuable : UPDATE montant bloqué (P0001)');

SELECT throws_ok(
  $$ UPDATE quote SET status = 'refused'
     WHERE id = 'f0000000-0000-0000-0000-000000000011' $$,
  'P0001', NULL,
  '⭐ quote signée immuable : changement de statut bloqué (P0001)');

SELECT throws_ok(
  $$ UPDATE quote SET deleted_at = now()
     WHERE id = 'f0000000-0000-0000-0000-000000000011' $$,
  'P0001', NULL,
  '⭐ quote signée immuable : soft-delete bloqué (P0001)');

SELECT * FROM finish();
ROLLBACK;
