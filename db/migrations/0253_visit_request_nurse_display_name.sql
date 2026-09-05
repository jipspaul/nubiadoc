-- 0253_visit_request_nurse_display_name.sql
-- Corrige #6506 : dès qu'une infirmière accepte une visite à domicile, le
-- patient ne reçoit qu'un `nurse_id` opaque (`VisitDto`,
-- `api/src/nurse/requests.rs`) — aucun moyen de savoir qui vient chez lui,
-- alors que le symétrique (`patient_display_name`) est déjà visible côté
-- infirmière.
-- Un simple LEFT JOIN sur `nurse` échouerait pour toute infirmière non
-- `is_listed` : `nurse_public_read` (0233) ne laisse lire que les infirmières
-- listées, exactement le contournement jugé "impossible de façon fiable"
-- dans l'issue. Fonction SECURITY DEFINER dédiée (même pattern que
-- `user_nurse_memberships`, 0233, ou `settle_unmatched_visit_request`, 0251) :
-- le patient ne peut de toute façon interroger que ses propres demandes
-- (RLS `visit_request`), donc révéler le nom de l'infirmière qui LUI a été
-- assignée ne fuite rien de plus que ce que la visite physique révèle déjà.
CREATE FUNCTION visit_nurse_display_name(p_nurse_id uuid)
    RETURNS text
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET row_security = off
    SET search_path = public
AS $$
    SELECT display_name FROM nurse WHERE id = p_nurse_id;
$$;

ALTER FUNCTION visit_nurse_display_name(uuid) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION visit_nurse_display_name(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION visit_nurse_display_name(uuid) TO nubia_app;
