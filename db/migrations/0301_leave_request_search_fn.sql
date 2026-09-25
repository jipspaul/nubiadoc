-- 0301_leave_request_search_fn.sql
-- Corrige #7632 : `staff_leave.rs` affirme qu'un `leave_request.status =
-- 'approved'` EST l'indisponibilité du praticien (pas de duplication vers
-- `provider_unavailability`, modèle différent — scopé `app_user` et non
-- `provider`), mais aucune requête ne consultait jamais cette table hors de
-- son propre module : un congé validé n'avait strictement aucun effet, le
-- praticien restait réservable en ligne (`/search/slots`) chaque jour de son
-- congé.
--
-- Même contrainte RLS que `provider_unavailable_at` (migration 0220) :
-- `leave_request` est sous FORCE ROW LEVEL SECURITY avec une policy qui
-- exige `app.current_cabinet_id` (0300), or `/search/slots` et
-- `/search/providers` sont des routes PUBLIQUES sans JWT qui ne posent
-- jamais ce GUC — un `NOT EXISTS` direct ne verrait donc aucune ligne. Même
-- pattern : fonction `SECURITY DEFINER` avec `row_security = off`, dédiée à
-- ce seul besoin (juste provider_id/starts_at/ends_at, jamais `kind`).
--
-- `leave_request.user_id` référence `app_user(id)` directement (congés =
-- toute l'équipe), pas `provider(id)` (scopé praticien) : jointure via
-- `practitioner` (`practitioner.user_id` = `leave_request.user_id`,
-- `provider.practitioner_id` = `practitioner.id`) pour retrouver le
-- `provider_id` utilisé par la recherche publique.

CREATE FUNCTION provider_on_leave_at(
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
    SELECT 1
    FROM leave_request lr
    JOIN practitioner pr ON pr.user_id = lr.user_id
    JOIN provider p ON p.practitioner_id = pr.id
    WHERE p.id = p_provider_id
      AND lr.status = 'approved'
      AND lr.starts_at < p_ends_at
      AND lr.ends_at > p_starts_at
  );
$$;

ALTER FUNCTION provider_on_leave_at(uuid, timestamptz, timestamptz) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION provider_on_leave_at(uuid, timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION provider_on_leave_at(uuid, timestamptz, timestamptz) TO nubia_app;
