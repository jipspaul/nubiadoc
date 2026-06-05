-- 0040_marketplace_provider_seed.sql
-- Données de test pour l'annuaire marketplace : 1 establishment + 1 provider
-- (is_listed=true, rpps_verified=true) nécessaires aux assertions pgTAP de
-- 06_marketplace_provider.sql (exécutés avant make seed en CI).
-- Cabinet et compte fictifs propres à cet espace de test (UUID e0000000-…,
-- hors seed.sql qui utilise 11111111-… et a0000000-…).
-- Règle métier : is_listed=true uniquement si rpps_verified=true (docs/07 §4.7).
-- Issue : #531

-- Cabinet fictif (requis par provider.cabinet_id NOT NULL).
-- nubia_owner a BYPASSRLS → INSERT sans GUC.
INSERT INTO cabinet (id, raison_sociale, siret, specialite, settings) VALUES
  ('e0000000-0000-0000-0000-000000000001', 'Cabinet Test Annuaire', '00000000000001',
   'dentaire', '{}')
ON CONFLICT (id) DO NOTHING;

-- Compte pro fictif (requis par provider.user_id NOT NULL depuis 0019).
INSERT INTO app_user (id, email, password_hash, kind, rpps, status) VALUES
  ('e0000000-0000-0000-0000-0000000000a1', 'test.annuaire@test.nubia',
   'SEED_PLACEHOLDER', 'pro', '99999999901', 'active')
ON CONFLICT (id) DO NOTHING;

-- Établissement géolocalisé (geo nullable — PostGIS geography(Point,4326)).
INSERT INTO establishment (id, name, address, geo) VALUES
  ('e0000000-0000-0000-0000-0000000000e1',
   'Centre Nubia Test',
   '{"rue":"1 allée des Tests","cp":"75001","ville":"Paris"}',
   ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326)::geography)
ON CONFLICT (id) DO NOTHING;

-- Provider listé (is_listed=true) parce que rpps_verified=true.
INSERT INTO provider (id, cabinet_id, user_id, establishment_id, display_name,
                      rpps, rpps_verified, is_listed) VALUES
  ('e0000000-0000-0000-0000-0000000000f1',
   'e0000000-0000-0000-0000-000000000001',
   'e0000000-0000-0000-0000-0000000000a1',
   'e0000000-0000-0000-0000-0000000000e1',
   'Dr Annuaire Test', '99999999901', true, true)
ON CONFLICT (id) DO NOTHING;
