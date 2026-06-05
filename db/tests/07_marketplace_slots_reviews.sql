-- 07_marketplace_slots_reviews.sql — Contrat availability_slot + review (issue #532).
-- pgTAP. Exécuté par pg_prove (sous nubia_app). Réf. docs/05 §9.2-§9.3.
BEGIN;
SELECT plan(5);

-- Tables présentes (0009)
SELECT has_table('availability_slot', 'availability_slot existe');
SELECT has_table('review',            'review existe');

-- Clé étrangère availability_slot → provider (0009)
SELECT fk_ok('availability_slot', 'provider_id', 'provider', 'id',
  'availability_slot.provider_id FK vers provider.id');

-- Index (provider_id, starts_at) avec le nom normalisé (0041)
SELECT has_index('availability_slot', 'slot_provider_time_idx',
  ARRAY['provider_id', 'starts_at'],
  'availability_slot : index slot_provider_time_idx (provider_id, starts_at)');

-- Contrainte CHECK rating 1..5 nommée review_rating_check (0009)
SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'review'::regclass AND conname = 'review_rating_check'
  ),
  'review : contrainte review_rating_check présente (CHECK rating BETWEEN 1 AND 5)'
);

SELECT finish();
ROLLBACK;
