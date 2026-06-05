-- 06_marketplace_provider.sql — Contrat establishment / provider + index géo (issue #531).
-- pgTAP. Exécuté par pg_prove (sous nubia_app). Réf. docs/05 §9.2-§9.3.
BEGIN;
SELECT plan(15);

SELECT has_table('establishment');
SELECT has_table('provider');

-- establishment : colonnes structurelles clés
SELECT has_column('establishment', 'name',    'establishment.name présent');
SELECT has_column('establishment', 'address', 'establishment.address présent');
SELECT has_column('establishment', 'geo',     'establishment.geo présent (PostGIS)');
SELECT col_not_null('establishment', 'name',  'establishment.name NOT NULL');

-- provider : colonnes métier
SELECT has_column('provider', 'rpps_verified',  'provider.rpps_verified présent');
SELECT col_not_null('provider', 'rpps_verified', 'provider.rpps_verified NOT NULL');
SELECT has_column('provider', 'is_listed',      'provider.is_listed présent');
SELECT col_not_null('provider', 'is_listed',    'provider.is_listed NOT NULL');

-- Clés étrangères (docs/05 §9.3)
SELECT fk_ok('provider', 'specialty_id',     'specialty',     'id');
SELECT fk_ok('provider', 'establishment_id', 'establishment', 'id');
SELECT fk_ok('provider', 'cabinet_id',       'cabinet',       'id');

-- Index géo GiST pour la recherche géographique (PostGIS, 0012)
SELECT has_index('provider', 'provider_geo_idx', ARRAY['geo'],
  'provider : index géo GiST présent (0012)');

-- Seed : au moins 1 provider is_listed=true visible via policy provider_public_read
-- (données chargées en 0040 ; renforcées par make seed)
SELECT ok(
  EXISTS(SELECT 1 FROM provider WHERE is_listed = true),
  'seed : provider is_listed=true présent (0040)'
);

SELECT finish();
ROLLBACK;
