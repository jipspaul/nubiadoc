-- 16_billing_clinical.sql — pgTAP : quote, treatment_plan, prescription, payment.idempotency_key.
-- Réf. : docs/12-api-reference.md §16-17, db/migrations/0006, 0010, 0051, 0061.
-- Issue : #778
-- Exécuté sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
BEGIN;
SELECT * FROM no_plan();

-- ===========================================================================
-- Fixtures — préfixe 77800000-... (propre à cette suite, pas de collision)
-- Cabinet 778-A (tenant principal) : praticien + patient.
-- Cabinet 778-B (tenant tiers) : pour tests cross-tenant.
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('77800000-0000-0000-0000-000000000001', 'Cabinet 778-A');

INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('77800000-0000-0000-0000-0000000000a1',
          'practitioner.778@example.test', '$argon2id$fixture', 'pro');

INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('77800000-0000-0000-0000-0000000000b1',
          '77800000-0000-0000-0000-000000000001',
          '77800000-0000-0000-0000-0000000000a1');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('77800000-0000-0000-0000-0000000000c1',
          '77800000-0000-0000-0000-000000000001', 'Lucie', '778A');

-- Cabinet 778-B
SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000002';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('77800000-0000-0000-0000-000000000002', 'Cabinet 778-B');

INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('77800000-0000-0000-0000-0000000000c2',
          '77800000-0000-0000-0000-000000000002', 'Paul', '778B');

-- ===========================================================================
-- 1. QUOTE — devis signé immuable (trigger enforce_quote_immutable, 0051)
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000001';

-- Créer un devis en draft
INSERT INTO quote (id, cabinet_id, patient_id, status)
  VALUES ('77800000-0000-0000-0000-000000000010',
          '77800000-0000-0000-0000-000000000001',
          '77800000-0000-0000-0000-0000000000c1',
          'draft');

-- 1.1 Trigger présent sur quote
SELECT ok(
  EXISTS(SELECT 1 FROM pg_trigger t
         JOIN pg_class c ON c.oid = t.tgrelid
         WHERE c.relname = 'quote' AND t.tgname = 'quote_signed_immutable'),
  'quote : trigger quote_signed_immutable présent (0051)');

-- 1.2 Devis draft → UPDATE autorisé (trigger ne bloque pas)
SELECT lives_ok(
  $$ UPDATE quote SET total_amount = 100.00
     WHERE id = '77800000-0000-0000-0000-000000000010' $$,
  'quote draft : UPDATE montant autorisé (non signé)');

-- Signer le devis
UPDATE quote SET status = 'signed', signed_at = now()
  WHERE id = '77800000-0000-0000-0000-000000000010';

-- 1.3 Devis signé → tout UPDATE bloqué (P0001 = raise exception du trigger)
SELECT throws_ok(
  $$ UPDATE quote SET total_amount = 9999.99
     WHERE id = '77800000-0000-0000-0000-000000000010' $$,
  'P0001', NULL,
  '⭐ quote signée immuable : UPDATE montant bloqué (P0001)');

SELECT throws_ok(
  $$ UPDATE quote SET status = 'refused'
     WHERE id = '77800000-0000-0000-0000-000000000010' $$,
  'P0001', NULL,
  '⭐ quote signée immuable : changement de statut bloqué (P0001)');

-- ===========================================================================
-- 2. TREATMENT_PLAN — RLS isolation tenant
-- ===========================================================================

-- 2.1 Praticien cabinet A insère un plan de traitement → OK
SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000001';
SELECT lives_ok(
  $$ INSERT INTO treatment_plan (id, cabinet_id, patient_id, practitioner_id, title)
     VALUES ('77800000-0000-0000-0000-000000000020',
             '77800000-0000-0000-0000-000000000001',
             '77800000-0000-0000-0000-0000000000c1',
             '77800000-0000-0000-0000-0000000000b1',
             'Plan implantaire 778-A') $$,
  '⭐ treatment_plan : INSERT praticien cabinet A → OK');

-- Plan de cabinet B
SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000002';
INSERT INTO treatment_plan (id, cabinet_id, patient_id, title)
  VALUES ('77800000-0000-0000-0000-000000000021',
          '77800000-0000-0000-0000-000000000002',
          '77800000-0000-0000-0000-0000000000c2',
          'Plan 778-B');

-- 2.2 Fail-closed : sans GUC → 0 plan visible
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM treatment_plan
   WHERE id IN ('77800000-0000-0000-0000-000000000020',
                '77800000-0000-0000-0000-000000000021')),
  0,
  '⭐ fail-closed treatment_plan : 0 plan visible sans app.current_cabinet_id');

-- 2.3 Contexte cabinet A → 1 plan (le sien), 0 du cabinet B
SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM treatment_plan
   WHERE id IN ('77800000-0000-0000-0000-000000000020',
                '77800000-0000-0000-0000-000000000021')),
  1,
  'treatment_plan contexte A : 1 plan visible (le sien)');

SELECT is(
  (SELECT count(*)::int FROM treatment_plan
   WHERE id = '77800000-0000-0000-0000-000000000021'),
  0,
  '⭐ cross-tenant treatment_plan : cabinet A voit 0 plan de cabinet B');

-- 2.4 Contexte cabinet B → 0 plan de cabinet A
SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000002';
SELECT is(
  (SELECT count(*)::int FROM treatment_plan
   WHERE id = '77800000-0000-0000-0000-000000000020'),
  0,
  '⭐ cross-tenant treatment_plan : cabinet B voit 0 plan de cabinet A');

-- 2.5 WITH CHECK : écriture cross-tenant refusée
SELECT throws_ok(
  $$ INSERT INTO treatment_plan (cabinet_id, patient_id, title)
     VALUES ('77800000-0000-0000-0000-000000000001',
             '77800000-0000-0000-0000-0000000000c2',
             'Plan pirate') $$,
  '42501', NULL,
  '⭐ WITH CHECK treatment_plan : INSERT cross-tenant refusé (42501)');

-- ===========================================================================
-- 3. PRESCRIPTION — RLS + soft-delete (pas de DELETE dur)
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000001';

-- 3.1 Praticien cabinet A insère une ordonnance → OK
SELECT lives_ok(
  $$ INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status)
     VALUES ('77800000-0000-0000-0000-000000000030',
             '77800000-0000-0000-0000-000000000001',
             '77800000-0000-0000-0000-0000000000c1',
             '77800000-0000-0000-0000-0000000000b1',
             'draft') $$,
  '⭐ prescription : INSERT praticien cabinet A → OK');

-- Ordonnance cabinet B
SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000002';
INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status)
  VALUES ('77800000-0000-0000-0000-000000000031',
          '77800000-0000-0000-0000-000000000002',
          '77800000-0000-0000-0000-0000000000c2',
          '77800000-0000-0000-0000-0000000000b1',  -- même praticien_id (hors scope RLS)
          'draft');

-- 3.2 Fail-closed : sans GUC → 0 prescription visible
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM prescription
   WHERE id IN ('77800000-0000-0000-0000-000000000030',
                '77800000-0000-0000-0000-000000000031')),
  0,
  '⭐ fail-closed prescription : 0 ordonnance visible sans app.current_cabinet_id');

-- 3.3 Contexte cabinet A → 1 prescription (la sienne)
SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000001';
SELECT is(
  (SELECT count(*)::int FROM prescription
   WHERE id IN ('77800000-0000-0000-0000-000000000030',
                '77800000-0000-0000-0000-000000000031')),
  1,
  'prescription contexte A : 1 ordonnance visible (la sienne)');

-- 3.4 Cross-tenant : cabinet A ne voit pas l'ordonnance de cabinet B
SELECT is(
  (SELECT count(*)::int FROM prescription
   WHERE id = '77800000-0000-0000-0000-000000000031'),
  0,
  '⭐ cross-tenant prescription : cabinet A voit 0 ordonnance de cabinet B');

-- 3.5 Soft-delete : deleted_at posé → non visible avec filtre applicatif standard
UPDATE prescription SET deleted_at = now()
  WHERE id = '77800000-0000-0000-0000-000000000030';

SELECT is(
  (SELECT count(*)::int FROM prescription
   WHERE id = '77800000-0000-0000-0000-000000000030'
     AND deleted_at IS NULL),
  0,
  '⭐ soft-delete prescription : ordonnance avec deleted_at IS NOT NULL invisible (filtre applicatif)');

-- 3.6 La ligne soft-deleted existe toujours en base (pas de DELETE dur)
SELECT is(
  (SELECT count(*)::int FROM prescription
   WHERE id = '77800000-0000-0000-0000-000000000030'),
  1,
  '⭐ soft-delete prescription : ligne toujours présente en base (pas de DELETE dur)');

-- ===========================================================================
-- 4. PAYMENT.IDEMPOTENCY_KEY — contrainte UNIQUE (0061)
-- ===========================================================================

SET LOCAL app.current_cabinet_id = '77800000-0000-0000-0000-000000000001';

-- Insérer un premier paiement avec idempotency_key
INSERT INTO payment (id, cabinet_id, patient_id, amount, kind, provider, status, idempotency_key)
  VALUES ('77800000-0000-0000-0000-000000000040',
          '77800000-0000-0000-0000-000000000001',
          '77800000-0000-0000-0000-0000000000c1',
          150.00, 'deposit', 'stripe', 'paid',
          'idem-key-778-001');

-- 4.1 La contrainte UNIQUE est bien présente sur payment.idempotency_key
SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(c.conkey)
    WHERE t.relname = 'payment'
      AND c.contype = 'u'
      AND a.attname = 'idempotency_key'
  ),
  'payment : contrainte UNIQUE sur idempotency_key présente (0061)');

-- 4.2 Rejeu avec le même idempotency_key → violation de contrainte (23505)
SELECT throws_ok(
  $$ INSERT INTO payment (cabinet_id, patient_id, amount, kind, provider, status, idempotency_key)
     VALUES ('77800000-0000-0000-0000-000000000001',
             '77800000-0000-0000-0000-0000000000c1',
             150.00, 'deposit', 'stripe', 'paid',
             'idem-key-778-001') $$,
  '23505', NULL,
  '⭐ payment.idempotency_key : insertion doublon = violation contrainte UNIQUE (23505)');

-- 4.3 NULL n'est pas soumis à la contrainte UNIQUE (plusieurs paiements sans clé = OK)
SELECT lives_ok(
  $$ INSERT INTO payment (cabinet_id, patient_id, amount, kind, provider, status)
     VALUES ('77800000-0000-0000-0000-000000000001',
             '77800000-0000-0000-0000-0000000000c1',
             50.00, 'installment', 'stripe', 'pending') $$,
  'payment sans idempotency_key (NULL) : pas de violation (NULLs non soumis à UNIQUE)');

SELECT lives_ok(
  $$ INSERT INTO payment (cabinet_id, patient_id, amount, kind, provider, status)
     VALUES ('77800000-0000-0000-0000-000000000001',
             '77800000-0000-0000-0000-0000000000c1',
             50.00, 'installment', 'stripe', 'pending') $$,
  'payment sans idempotency_key (NULL) : deuxième NULL accepté aussi');

SELECT * FROM finish();
ROLLBACK;
