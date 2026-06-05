-- 07_marketplace_slots_reviews.sql — Contrat availability_slot / review (issue #532).
-- pgTAP. Exécuté par pg_prove (sous nubia_app). Réf. docs/05 §9.2-§9.3.
BEGIN;
SELECT plan(9);

SELECT has_table('availability_slot');
SELECT fk_ok('availability_slot', 'provider_id', 'provider', 'id');
SELECT has_index('availability_slot', 'slot_provider_time_idx', ARRAY['provider_id','starts_at'],
  'availability_slot : index provider+time présent');
SELECT col_has_check('availability_slot', 'status',
  'availability_slot.status check (open/held/booked)');

SELECT has_table('review');
SELECT fk_ok('review', 'provider_id',        'provider',        'id');
SELECT fk_ok('review', 'patient_account_id', 'patient_account', 'id');
SELECT col_has_check('review', 'rating',
  'review.rating check (1–5)');
SELECT col_has_check('review', 'status',
  'review.status check (pending/published/rejected)');

SELECT finish();
ROLLBACK;
