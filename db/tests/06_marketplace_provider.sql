-- 06_marketplace_provider.sql — Contrat establishment + provider (issue #531).
-- pgTAP. Exécuté par pg_prove (sous nubia_app). Réf. docs/05 §9.2-§9.3.
-- Tables créées en 0009, colonnes supplémentaires en 0019, index PostGIS en 0012.
BEGIN;
SELECT plan(13);

-- Tables existent
SELECT has_table('establishment');
SELECT has_table('provider');

-- Colonnes clés
SELECT has_column('establishment', 'geo');
SELECT has_column('provider', 'rpps_verified');
SELECT has_column('provider', 'is_listed');
SELECT has_column('provider', 'geo');

-- Clés étrangères
SELECT fk_ok('provider', 'specialty_id',     'specialty',     'id');
SELECT fk_ok('provider', 'establishment_id', 'establishment', 'id');
SELECT fk_ok('provider', 'practitioner_id',  'practitioner',  'id');
SELECT fk_ok('provider', 'cabinet_id',       'cabinet',       'id');

-- Index géographique PostGIS (GiST — requis par ST_DWithin / "autour de moi")
SELECT has_index('provider', 'provider_geo_idx');

-- Fixtures minimales dans la transaction pour vérifier la règle is_listed.
-- (nubia_app INSERT dans provider nécessite le contexte cabinet : provider_cabinet_manage)
SET LOCAL app.current_cabinet_id = 'c0000000-0000-0000-0000-000000000531';
INSERT INTO cabinet (id, raison_sociale) VALUES ('c0000000-0000-0000-0000-000000000531', 'Cabinet Test 531');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('c1000000-0000-0000-0000-000000000531', 'test531@nubiadoc.test', 'x', 'pro');
INSERT INTO establishment (id, name, address) VALUES
  ('c2000000-0000-0000-0000-000000000531', 'Établissement Test 531',
   '{"rue":"1 rue Test","cp":"75001","ville":"Paris"}');
INSERT INTO provider (id, cabinet_id, user_id, establishment_id, display_name, rpps_verified, is_listed)
  VALUES ('c3000000-0000-0000-0000-000000000531',
          'c0000000-0000-0000-0000-000000000531',
          'c1000000-0000-0000-0000-000000000531',
          'c2000000-0000-0000-0000-000000000531',
          'Dr Test 531', true, true);

-- Règle métier : provider rpps_verified → is_listed autorisé (docs/07 §4.7)
SELECT ok(
  (SELECT is_listed FROM provider WHERE id = 'c3000000-0000-0000-0000-000000000531'),
  'seed provider is_listed');

-- Annuaire public : provider is_listed=true visible hors contexte cabinet
-- (policy provider_public_read FOR SELECT USING is_listed = true, cf. 0011)
RESET app.current_cabinet_id;
SELECT ok(
  (SELECT count(*)::int FROM provider WHERE id = 'c3000000-0000-0000-0000-000000000531') = 1,
  'provider listé visible hors contexte cabinet (annuaire public)');

SELECT finish();
ROLLBACK;
