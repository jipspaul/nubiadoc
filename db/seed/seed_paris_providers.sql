-- seed_paris_providers.sql — annuaire de démo : 14 praticiens dentaires répartis
-- dans Paris, géolocalisés, notés, avec ~3 semaines de créneaux ouverts.
--
-- But : rendre la recherche patient (annuaire + carte) réellement utilisable.
-- Idempotent : ré-exécutable (ON CONFLICT sur les entités + régénération des
-- créneaux ouverts depuis now()). Chargé par le rôle nubia_owner (BYPASSRLS)
-- comme seed_slots.sql. À lancer après seed.sql.
--
-- UUID déterministes, préfixes par table (suffixe = index 01..14) :
--   app_user   90a10000-…-0000000000NN
--   cabinet    90ca0000-…-0000000000NN
--   practitioner 90c70000-…-0000000000NN
--   provider   90de0000-…-0000000000NN
\set ON_ERROR_STOP on

BEGIN;

-- Jeu de données source (index, nom, lat, lng, specialty_id, secteur, note,
-- nb_avis, langues, PMR, téléconsult, tiers-payant, bio).
CREATE TEMP TABLE _paris(
  n int, name text, lat double precision, lng double precision,
  specialty_id uuid, sector text, rating numeric(2,1), rcount int,
  langs text[], pmr boolean, teleconsult boolean, tp boolean, bio text
) ON COMMIT DROP;

INSERT INTO _paris VALUES
  (1,  'Dr Camille Laurent',   48.8592, 2.3417, 'd2000000-0000-0000-0000-000000000001', '1', 4.8, 132, ARRAY['fr','en'],       true,  true,  true,  'Chirurgien-dentiste, omnipratique et esthétique du sourire. Cabinet Louvre.'),
  (2,  'Dr Antoine Mercier',   48.8666, 2.3410, 'd2000000-0000-0000-0000-000000000002', '2', 4.6, 88,  ARRAY['fr','en','es'], true,  false, true,  'Implantologie et chirurgie orale. Prise en charge des cas complexes.'),
  (3,  'Dr Sophie Nguyen',     48.8637, 2.3615, 'd2000000-0000-0000-0000-000000000003', '1', 4.9, 210, ARRAY['fr','en','vi'], true,  true,  true,  'Orthodontie adulte et enfant, gouttières transparentes. Marais.'),
  (4,  'Dr Julien Faure',      48.8548, 2.3560, 'd2000000-0000-0000-0000-000000000001', '2', 4.3, 54,  ARRAY['fr'],           false, false, true,  'Soins conservateurs, parodontologie. Île Saint-Louis.'),
  (5,  'Dr Inès Bernard',      48.8448, 2.3471, 'd2000000-0000-0000-0000-000000000001', '1', 4.7, 176, ARRAY['fr','en','ar'], true,  true,  true,  'Omnipratique, urgences dentaires. Quartier Latin.'),
  (6,  'Dr Thomas Girard',     48.8490, 2.3330, 'd2000000-0000-0000-0000-000000000002', '2', 4.5, 97,  ARRAY['fr','en'],       true,  false, false, 'Implants et greffes osseuses. Saint-Germain-des-Prés.'),
  (7,  'Dr Léa Rousseau',      48.8566, 2.3126, 'd2000000-0000-0000-0000-000000000003', '1', 4.8, 143, ARRAY['fr','en','it'], true,  true,  true,  'Orthodontie invisible, esthétique. Tour Eiffel / 7e.'),
  (8,  'Dr Nicolas Petit',     48.8726, 2.3120, 'd2000000-0000-0000-0000-000000000001', '2', 4.2, 41,  ARRAY['fr','en'],       false, false, true,  'Dentisterie générale et pédiatrique. Champs-Élysées.'),
  (9,  'Dr Amélie Dubois',     48.8770, 2.3390, 'd2000000-0000-0000-0000-000000000001', '1', 4.9, 265, ARRAY['fr','en','de'], true,  true,  true,  'Esthétique dentaire, blanchiment, facettes. Opéra / 9e.'),
  (10, 'Dr Karim Haddad',      48.8760, 2.3590, 'd2000000-0000-0000-0000-000000000002', '2', 4.4, 72,  ARRAY['fr','en','ar'], true,  false, true,  'Implantologie, réhabilitation complète. Gare de l''Est / 10e.'),
  (11, 'Dr Chloé Moreau',      48.8590, 2.3790, 'd2000000-0000-0000-0000-000000000003', '1', 4.6, 118, ARRAY['fr','en'],       true,  true,  true,  'Orthodontie et fonction. Bastille / 11e.'),
  (12, 'Dr Hugo Lefevre',      48.8410, 2.3880, 'd2000000-0000-0000-0000-000000000001', '2', 4.1, 33,  ARRAY['fr'],           false, false, false, 'Soins courants, détartrage, urgences. Bercy / 12e.'),
  (13, 'Dr Manon Garnier',     48.8330, 2.3260, 'd2000000-0000-0000-0000-000000000001', '1', 4.7, 159, ARRAY['fr','en','pt'], true,  true,  true,  'Omnipratique douce, patients anxieux. Montparnasse / 14e.'),
  (14, 'Dr Raphaël Simon',     48.8600, 2.2760, 'd2000000-0000-0000-0000-000000000002', '2', 4.5, 101, ARRAY['fr','en'],       true,  false, true,  'Implants et parodontie. Trocadéro / 16e.');

-- ── app_user (comptes pro techniques — non destinés au login) ────────────────
INSERT INTO app_user (id, email, password_hash, kind, status, first_name, last_name)
SELECT
  ('90a10000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'paris-praticien-' || n || '@nubia-demo.test',
  'SEED_PLACEHOLDER', 'pro', 'active',
  split_part(name, ' ', 2), split_part(name, ' ', 3)
FROM _paris
ON CONFLICT (id) DO NOTHING;

-- ── cabinet ──────────────────────────────────────────────────────────────────
INSERT INTO cabinet (id, raison_sociale, specialite)
SELECT
  ('90ca0000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  'Cabinet ' || split_part(name, ' ', 3), 'dentaire'
FROM _paris
ON CONFLICT (id) DO NOTHING;

-- ── practitioner ─────────────────────────────────────────────────────────────
INSERT INTO practitioner (id, cabinet_id, user_id, rpps, specialite)
SELECT
  ('90c70000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  ('90ca0000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  ('90a10000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  '1010000' || lpad(n::text, 4, '0'), 'dentaire'
FROM _paris
ON CONFLICT (id) DO UPDATE SET cabinet_id = EXCLUDED.cabinet_id;

-- ── provider (annuaire : listé, géolocalisé, noté) ───────────────────────────
INSERT INTO provider (
  id, practitioner_id, cabinet_id, user_id, display_name, rpps, rpps_verified,
  specialty_id, sector, languages, pmr, teleconsult, accepts_new_patients,
  bio, geo, rating_avg, rating_count, is_listed, tiers_payant
)
SELECT
  ('90de0000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  ('90c70000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  ('90ca0000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  ('90a10000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
  name, '1010000' || lpad(n::text, 4, '0'), true,
  specialty_id, sector, langs, pmr, teleconsult, true,
  bio, ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography, rating, rcount, true, tp
FROM _paris
ON CONFLICT (id) DO UPDATE SET
  cabinet_id   = EXCLUDED.cabinet_id,
  geo          = EXCLUDED.geo,
  rating_avg   = EXCLUDED.rating_avg,
  rating_count = EXCLUDED.rating_count,
  is_listed    = true,
  bio          = EXCLUDED.bio,
  languages    = EXCLUDED.languages;

-- ── créneaux ouverts : régénérés depuis maintenant ───────────────────────────
-- On repart propre : supprime les créneaux `open` non réservés de ces
-- praticiens, puis regénère 3 semaines de créneaux 30 min (jours ouvrés,
-- 09:00–12:30 et 14:00–17:30) à venir.
DELETE FROM availability_slot
WHERE provider_id IN (SELECT ('90de0000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid FROM _paris)
  AND status = 'open';

INSERT INTO availability_slot (
  id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at,
  status, online_booking
)
SELECT
  gen_random_uuid(),
  ('90de0000-0000-4000-8000-0000000000' || lpad(p.n::text, 2, '0'))::uuid,
  ('90ca0000-0000-4000-8000-0000000000' || lpad(p.n::text, 2, '0'))::uuid,
  ('90c70000-0000-4000-8000-0000000000' || lpad(p.n::text, 2, '0'))::uuid,
  ts, ts + interval '30 minutes', 'open', true
FROM _paris p
CROSS JOIN LATERAL (
  SELECT (d::date + t) AT TIME ZONE 'Europe/Paris' AS ts
  FROM generate_series(current_date, current_date + interval '20 days', interval '1 day') d
  CROSS JOIN unnest(ARRAY[
    '09:00','09:30','10:00','10:30','11:00','11:30','12:00',
    '14:00','14:30','15:00','15:30','16:00','16:30','17:00','17:30'
  ]::time[]) t
  WHERE extract(dow FROM d) BETWEEN 1 AND 5
) slots
WHERE ts > now();

COMMIT;

-- Récapitulatif (visible dans le log de seed).
SELECT
  (SELECT count(*) FROM provider WHERE id::text LIKE '90de0000-%') AS praticiens_paris,
  (SELECT count(*) FROM availability_slot s
     WHERE s.provider_id::text LIKE '90de0000-%' AND s.status = 'open') AS creneaux_ouverts;

-- ═══════════════════════════════════════════════════════════════════════════
-- ENV DE TEST SECRÉTARIAT — Hugo Marin (f1) et Claire Lefèvre (f2, déplacée du
-- Secrétariat B → A), tous deux praticiens du Cabinet Lyon, gérés par le
-- Secrétariat A (sonia.accueil@cabinet-lyon.test). Rôle nubia_owner
-- (BYPASSRLS). Idempotent.
--   Cabinet Lyon  = 11111111-1111-1111-1111-111111111111
--   Secrétariat A = 19870000-0000-0000-0000-000000000001
--
-- ATTENTION (bug #3542, agenda-cross-cabinet) : les 14 praticiens d'annuaire
-- Paris (90c70000-…/90de0000-…) restent chacun dans leur propre cabinet
-- (90ca0000-…-NN, cf. INSERT plus haut). Ce sont des fiches annuaire pour la
-- recherche patient, PAS des membres du Cabinet Lyon — ne pas les rattacher
-- au Cabinet Lyon ni au Secrétariat A : `get_cabinet_agenda` (scheduling.rs)
-- filtre uniquement par `practitioner.cabinet_id`, tout rattachement ici les
-- ferait apparaître (et être planifiables) dans l'agenda du cabinet Lyon.
-- ═══════════════════════════════════════════════════════════════════════════
BEGIN;

-- Désactiver tout lien secrétariat actif ≠ A pour Hugo/Claire (ex : Claire → B).
UPDATE provider_secretariat SET active = false
 WHERE active
   AND secretariat_id <> '19870000-0000-0000-0000-000000000001'
   AND provider_id IN ('f0000000-0000-0000-0000-0000000000f1',
                       'f0000000-0000-0000-0000-0000000000f2');

-- Lier Hugo + Claire au Secrétariat A (sans doublon actif).
INSERT INTO provider_secretariat (provider_id, secretariat_id, active)
SELECT p.id, '19870000-0000-0000-0000-000000000001', true
  FROM provider p
 WHERE p.id IN ('f0000000-0000-0000-0000-0000000000f1',
                'f0000000-0000-0000-0000-0000000000f2')
   AND NOT EXISTS (
        SELECT 1 FROM provider_secretariat ps
         WHERE ps.provider_id = p.id
           AND ps.secretariat_id = '19870000-0000-0000-0000-000000000001'
           AND ps.active);

COMMIT;

\echo '✓ env test secrétariat : Hugo Marin + Claire Lefèvre rattachés au Secrétariat A'
