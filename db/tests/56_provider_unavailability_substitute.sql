-- 56_provider_unavailability_substitute.sql — Contrat de
-- provider_unavailability.substitute_practitioner_id (#4158). Vérifie :
-- NULL accepté (comportement historique inchangé) · référence provider
-- valide acceptée · référence provider inexistante rejetée (FK) · RLS
-- provider_unavailability_cabinet_isolation (migration 0116) inchangée —
-- toujours scopée sur provider_id, pas sur la nouvelle colonne.
-- Exécuté par pg_prove sous nubia_app. Fixtures BEGIN…ROLLBACK.

BEGIN;
SELECT * FROM no_plan();

SET LOCAL app.current_cabinet_id = '05600000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale)
  VALUES ('05600000-0000-0000-0000-000000000001', 'Cabinet 56-substitute')
  ON CONFLICT DO NOTHING;

INSERT INTO provider (id, cabinet_id, display_name)
  VALUES
    ('05600000-0000-0000-0000-0000000000a1', '05600000-0000-0000-0000-000000000001', 'Dr Absent 56'),
    ('05600000-0000-0000-0000-0000000000a2', '05600000-0000-0000-0000-000000000001', 'Dr Remplaçant 56')
  ON CONFLICT DO NOTHING;

-- NULL accepté (comportement historique).
INSERT INTO provider_unavailability (id, provider_id, starts_at, ends_at, substitute_practitioner_id)
  VALUES ('05600000-0000-0000-0000-0000000000b1', '05600000-0000-0000-0000-0000000000a1',
          now(), now() + interval '1 day', NULL);

-- Référence provider valide acceptée.
INSERT INTO provider_unavailability (id, provider_id, starts_at, ends_at, substitute_practitioner_id)
  VALUES ('05600000-0000-0000-0000-0000000000b2', '05600000-0000-0000-0000-0000000000a1',
          now() + interval '2 days', now() + interval '3 days',
          '05600000-0000-0000-0000-0000000000a2');

-- Les SELECT/INSERT suivants restent sous le même app.current_cabinet_id
-- (RLS FORCE) : sans lui, toute ligne serait invisible et les assertions
-- testeraient une absence de ligne plutôt que la valeur de la colonne.
SELECT is(
  (SELECT substitute_practitioner_id FROM provider_unavailability
     WHERE id = '05600000-0000-0000-0000-0000000000b1'),
  NULL::uuid,
  'substitute_practitioner_id NULL accepté (comportement historique inchangé)');

SELECT is(
  (SELECT substitute_practitioner_id FROM provider_unavailability
     WHERE id = '05600000-0000-0000-0000-0000000000b2'),
  '05600000-0000-0000-0000-0000000000a2'::uuid,
  '⭐ substitute_practitioner_id référence provider valide acceptée');

-- Référence provider inexistante rejetée (contrainte FK) — toujours sous le
-- bon app.current_cabinet_id, sinon c'est la RLS (WITH CHECK) qui échouerait
-- en premier et masquerait l'assertion FK visée.
SELECT throws_ok(
  $$INSERT INTO provider_unavailability (provider_id, starts_at, ends_at, substitute_practitioner_id)
    VALUES ('05600000-0000-0000-0000-0000000000a1', now(), now() + interval '1 day',
            '00000000-0000-0000-0000-000000000000')$$,
  '23503',
  NULL,
  '⭐ substitute_practitioner_id référence provider inexistante rejetée (FK)');

-- RLS inchangée : toujours scopée sur provider_id (migration 0116), pas sur
-- la nouvelle colonne — sans le bon app.current_cabinet_id, aucune ligne visible.
SET LOCAL app.current_cabinet_id = '05600000-0000-0000-0000-000000000099';
SELECT is(
  (SELECT count(*)::int FROM provider_unavailability
     WHERE id IN ('05600000-0000-0000-0000-0000000000b1', '05600000-0000-0000-0000-0000000000b2')),
  0,
  '⭐ RLS provider_unavailability_cabinet_isolation inchangée (scope provider_id)');
RESET app.current_cabinet_id;

SELECT * FROM finish();
ROLLBACK;
