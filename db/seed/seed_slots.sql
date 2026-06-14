-- =====================================================================
-- seed_slots.sql — réapprovisionne un pool de créneaux ouverts (démo + E2E)
--
-- Idempotent et non destructif : insère des créneaux `open` de 30 min pour les
-- praticiens démo sur les 30 prochains jours (jours ouvrés, matin + après-midi),
-- en sautant tout créneau qui chevauche un créneau non-`booked` ou un RDV actif
-- existant (contrainte EXCLUDE `slot_practitioner_no_overlap`).
--
-- À lancer après seed.sql (rôle nubia_owner — BYPASSRLS pour traverser la RLS
-- cabinet). Relancé à chaque démarrage de la dev-stack pour garder un pool frais.
-- =====================================================================
\set ON_ERROR_STOP on

-- Réparation : un créneau `open` dont l'horaire chevauche un RDV actif est en
-- réalité pris (le booking ne consomme pas toujours le créneau — ex. seed, ou
-- chemin cabinet). On le repasse à `booked` pour qu'il disparaisse de la
-- recherche (`/v1/search/slots` filtre `status = 'open'`). La recherche est un
-- endpoint public sans contexte RLS, elle ne peut donc pas exclure ces
-- chevauchements elle-même — d'où la normalisation côté données.
UPDATE availability_slot s SET status = 'booked', updated_at = now()
WHERE s.status = 'open'
  AND EXISTS (
    SELECT 1 FROM appointment a
    WHERE a.practitioner_id = s.practitioner_id
      AND a.status <> 'cancelled'
      AND a.deleted_at IS NULL
      AND tstzrange(a.starts_at, a.ends_at) && tstzrange(s.starts_at, s.ends_at)
  );

-- Les créneaux du jour issus du seed (horaires aléatoires « maintenant + ε »)
-- chevauchent les RDV du jour et se re-polluent au fil des consultations
-- démarrées. On les retire de la réservation : le pool propre (généré ci-dessous)
-- commence demain. La recherche partira ainsi toujours d'un créneau libre.
UPDATE availability_slot SET status = 'booked', updated_at = now()
WHERE status = 'open'
  AND starts_at < date_trunc('day', now()) + interval '1 day';

INSERT INTO availability_slot
  (provider_id, practitioner_id, cabinet_id, starts_at, ends_at, status, online_booking)
SELECT
  prov.provider_id,
  prov.practitioner_id,
  '11111111-1111-1111-1111-111111111111'::uuid,
  ts,
  ts + interval '30 minutes',
  'open',
  true
FROM (VALUES
  ('f0000000-0000-0000-0000-0000000000f1'::uuid, 'c0000000-0000-0000-0000-0000000000c1'::uuid),
  ('f0000000-0000-0000-0000-0000000000f2'::uuid, 'c0000000-0000-0000-0000-0000000000c2'::uuid)
) AS prov(provider_id, practitioner_id)
CROSS JOIN generate_series(1, 30) AS d(day)
CROSS JOIN (VALUES (8), (9), (10), (11), (14), (15), (16), (17)) AS h(hour)
CROSS JOIN LATERAL (
  SELECT (date_trunc('day', now()) + make_interval(days => d.day, hours => h.hour)) AS ts
) AS slot
WHERE extract(dow FROM slot.ts) BETWEEN 1 AND 5   -- lundi→vendredi
  AND NOT EXISTS (
    SELECT 1 FROM availability_slot s
    WHERE s.practitioner_id = prov.practitioner_id
      AND s.status <> 'booked'
      AND s.deleted_at IS NULL
      AND tstzrange(s.starts_at, s.ends_at) && tstzrange(slot.ts, slot.ts + interval '30 minutes')
  )
  AND NOT EXISTS (
    SELECT 1 FROM appointment a
    WHERE a.practitioner_id = prov.practitioner_id
      AND a.status <> 'cancelled'
      AND a.deleted_at IS NULL
      AND tstzrange(a.starts_at, a.ends_at) && tstzrange(slot.ts, slot.ts + interval '30 minutes')
  );

\echo '✓ pool de créneaux ouverts réapprovisionné (démo + E2E)'
