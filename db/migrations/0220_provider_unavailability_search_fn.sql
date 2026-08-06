-- 0220_provider_unavailability_search_fn.sql
-- Corrige #4655 : la clause d'exclusion `provider_unavailability` ajoutée par
-- #4647/#4649 dans marketplace.rs (UNAVAILABILITY_EXCLUSION_CLAUSE) est un
-- NOT EXISTS direct sur provider_unavailability, table sous
-- FORCE ROW LEVEL SECURITY avec policy `provider_unavailability_cabinet_isolation`
-- (0116) qui exige `app.current_cabinet_id`. /search/slots et /search/providers
-- sont des routes PUBLIQUES (pas de JWT, pas de SELECT set_config du GUC
-- cabinet) : la sous-requête RLS-scopée ne voit donc jamais aucune ligne, le
-- NOT EXISTS est toujours vrai et l'exclusion est un no-op silencieux — un
-- créneau couvert par une indisponibilité déclarée reste annoncé disponible
-- dans l'annuaire public, alors que la réservation réelle (RLS satisfaite via
-- le contexte cabinet patient authentifié, appointments_create.rs) le refuse
-- correctement en 409.
--
-- Fix : même pattern que try_claim_slot (0095) / resolve_slot_for_booking
-- (0128) — une fonction SECURITY DEFINER avec row_security=off, dédiée à ce
-- seul besoin (juste provider_id/starts_at/ends_at, jamais `reason`), plutôt
-- qu'élargir la policy RLS de la table à une lecture publique globale.

CREATE FUNCTION provider_unavailable_at(
  p_provider_id uuid,
  p_starts_at   timestamptz,
  p_ends_at     timestamptz
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1 FROM provider_unavailability pu
    WHERE pu.provider_id = p_provider_id
      AND pu.starts_at < p_ends_at
      AND pu.ends_at > p_starts_at
  );
$$;

ALTER FUNCTION provider_unavailable_at(uuid, timestamptz, timestamptz) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION provider_unavailable_at(uuid, timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION provider_unavailable_at(uuid, timestamptz, timestamptz) TO nubia_app;
