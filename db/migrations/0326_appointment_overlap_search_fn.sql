-- 0326_appointment_overlap_search_fn.sql
-- Corrige #8543 : `search_slots` (marketplace.rs, SLOT_BOOKABLE_CLAUSE) ne
-- confronte jamais `availability_slot` à `appointment` — seule la création
-- manuelle d'un créneau (scheduling.rs:3338-3356, #6237) refuse un créneau
-- qui chevauche un rendez-vous actif du même praticien. Un créneau annoncé
-- `is_available:true` par l'annuaire public peut donc chevaucher un RDV déjà
-- pris (RDV créé par une autre voie que `availability_slot`, ou grille
-- régénérée après coup sur un horaire déjà occupé) : la réservation réelle
-- se heurte alors systématiquement à la contrainte d'exclusion DB
-- `appointment_no_overlap` → 409 slot_taken, sur un créneau qui ne redevient
-- jamais réservable.
--
-- Même contrainte RLS que `provider_unavailable_at` (0220) / `provider_on_leave_at`
-- (0301) : `appointment` est sous FORCE ROW LEVEL SECURITY avec une policy
-- qui exige `app.current_cabinet_id` (0011), or `/search/slots` et
-- `/search/providers` sont des routes PUBLIQUES sans JWT qui ne posent jamais
-- ce GUC — un `NOT EXISTS` direct ne verrait donc aucune ligne et l'exclusion
-- serait un no-op silencieux. Même pattern : fonction `SECURITY DEFINER` avec
-- `row_security = off`, dédiée à ce seul besoin.
--
-- `availability_slot.practitioner_id` existe déjà en colonne directe (posée
-- par la création manuelle de créneau, scheduling.rs) : pas besoin de
-- jointure via `provider` comme pour `provider_on_leave_at`.

CREATE FUNCTION practitioner_has_active_appointment_at(
  p_practitioner_id uuid,
  p_starts_at       timestamptz,
  p_ends_at         timestamptz
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1 FROM appointment ap
    WHERE ap.practitioner_id = p_practitioner_id
      AND ap.status NOT IN ('cancelled', 'no_show')
      AND ap.starts_at < p_ends_at
      AND ap.ends_at > p_starts_at
  );
$$;

ALTER FUNCTION practitioner_has_active_appointment_at(uuid, timestamptz, timestamptz) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION practitioner_has_active_appointment_at(uuid, timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION practitioner_has_active_appointment_at(uuid, timestamptz, timestamptz) TO nubia_app;
