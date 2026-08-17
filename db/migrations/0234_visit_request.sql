-- 0234_visit_request.sql
-- Demande de visite infirmière à domicile + dispatch « offre aux proches,
-- premier·ère qui accepte gagne » (Uber v1, sans tracking GPS live).
-- Calqué sur pharmacy_order (0124, machine à états + RLS multi-ancre) et
-- claim_and_hold_slot (0120, accept concurrent-safe).
--
-- Deux ancres RLS permissives : le patient (GUC app.patient_account_id) voit et
-- crée ses demandes ; l'infirmière (GUC app.current_nurse_id) voit les demandes
-- qui lui sont OFFERTES (via visit_offer) puis, une fois acceptée, les siennes.
--
-- Machine à états :
--   requested → offered → accepted → en_route → arrived → done
--   + cancelled (patient, tant que non terminal) et expired (aucune acceptation).
-- L'insertion des offres et l'acceptation passent par des fonctions SECURITY
-- DEFINER (fan-out multi-infirmières + premier-accepté-gagne sérialisé).
-- Épic : app infirmières (Uber v1).

CREATE TABLE visit_request (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_account_id    UUID        NOT NULL REFERENCES patient_account(id),
    nurse_id              UUID        REFERENCES nurse(id),   -- NULL jusqu'à l'acceptation
    visit_geo             geography(Point, 4326) NOT NULL,   -- adresse géocodée de la visite
    address               JSONB       NOT NULL DEFAULT '{}',
    requested_acts        TEXT[]      NOT NULL DEFAULT '{}',  -- ex: {prise_de_sang,pansement,injection}
    notes                 TEXT,
    patient_display_name  TEXT        NOT NULL,               -- minimisé « Prénom N. » (cf. pharmacy_order)
    status                TEXT        NOT NULL DEFAULT 'requested'
        CHECK (status IN ('requested','offered','accepted','en_route','arrived','done','cancelled','expired')),
    scheduled_window_start TIMESTAMPTZ,
    scheduled_window_end   TIMESTAMPTZ,
    rejection_reason      TEXT,
    requested_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    offered_at            TIMESTAMPTZ,
    accepted_at           TIMESTAMPTZ,
    en_route_at           TIMESTAMPTZ,
    arrived_at            TIMESTAMPTZ,
    done_at               TIMESTAMPTZ,
    cancelled_at          TIMESTAMPTZ,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Une seule demande active par patient (l'acceptation/annulation/expiration libère).
CREATE UNIQUE INDEX visit_request_active_patient
    ON visit_request (patient_account_id)
    WHERE status IN ('requested','offered','accepted','en_route','arrived');

-- Tournée de l'infirmière (ses visites acceptées, filtre par statut) + suivi patient.
CREATE INDEX idx_visit_request_nurse_status ON visit_request (nurse_id, status);
CREATE INDEX idx_visit_request_account ON visit_request (patient_account_id);

-- Fan-out des offres aux infirmières proches (premier-accepté-gagne).
CREATE TABLE visit_offer (
    id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    visit_request_id UUID        NOT NULL REFERENCES visit_request(id) ON DELETE CASCADE,
    nurse_id         UUID        NOT NULL REFERENCES nurse(id) ON DELETE CASCADE,
    status           TEXT        NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending','accepted','declined','expired')),
    distance_m       DOUBLE PRECISION,
    offered_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at       TIMESTAMPTZ NOT NULL,
    responded_at     TIMESTAMPTZ,
    UNIQUE (visit_request_id, nurse_id)
);

CREATE INDEX idx_visit_offer_nurse_status ON visit_offer (nurse_id, status);

-- Append-only sauf transitions : pas de DELETE pour l'app (pattern pharmacy_order 0124).
REVOKE ALL ON visit_request FROM nubia_app;
GRANT SELECT, INSERT, UPDATE ON visit_request TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON visit_request TO nubia_seed;
-- visit_offer : écrit UNIQUEMENT par les fonctions SECURITY DEFINER (fan-out /
-- claim) ; l'app ne fait que lire (l'infirmière voit ses offres).
REVOKE ALL ON visit_offer FROM nubia_app;
GRANT SELECT ON visit_offer TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON visit_offer TO nubia_seed;

ALTER TABLE visit_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_request FORCE ROW LEVEL SECURITY;
ALTER TABLE visit_offer ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_offer FORCE ROW LEVEL SECURITY;

-- Patient : voit ses demandes, en crée (status 'requested' uniquement, non
-- assignée), et peut ANNULER tant que non terminal. WITH CHECK interdit de
-- forger une acceptation/transition infirmière.
CREATE POLICY visit_request_patient_select ON visit_request
    FOR SELECT TO nubia_app
    USING (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid);
CREATE POLICY visit_request_patient_insert ON visit_request
    FOR INSERT TO nubia_app
    WITH CHECK (
        patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        AND status = 'requested'
        AND nurse_id IS NULL
    );
CREATE POLICY visit_request_patient_cancel ON visit_request
    FOR UPDATE TO nubia_app
    USING (
        patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        AND status IN ('requested','offered','accepted','en_route','arrived')
    )
    WITH CHECK (
        patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        AND status = 'cancelled'
    );

-- Infirmière : voit les demandes qui LUI sont offertes (via une offre pending)
-- ainsi que celles qu'elle a acceptées (nurse_id), et fait avancer SES visites
-- (en_route → arrived → done). L'acceptation elle-même passe par claim_visit
-- (SECURITY DEFINER) — pas par cette policy (WITH CHECK n'autorise pas 'accepted').
CREATE POLICY visit_request_nurse_select ON visit_request
    FOR SELECT TO nubia_app
    USING (
        nurse_id = nullif(current_setting('app.current_nurse_id', true), '')::uuid
        OR id IN (
            SELECT vo.visit_request_id FROM visit_offer vo
            WHERE vo.nurse_id = nullif(current_setting('app.current_nurse_id', true), '')::uuid
              AND vo.status = 'pending'
        )
    );
CREATE POLICY visit_request_nurse_transition ON visit_request
    FOR UPDATE TO nubia_app
    USING (
        nurse_id = nullif(current_setting('app.current_nurse_id', true), '')::uuid
        AND status IN ('accepted','en_route','arrived')
    )
    WITH CHECK (
        nurse_id = nullif(current_setting('app.current_nurse_id', true), '')::uuid
        AND status IN ('en_route','arrived','done')
    );

CREATE POLICY visit_request_seed_all ON visit_request
    TO nubia_seed USING (true) WITH CHECK (true);

-- L'infirmière lit ses propres offres (file « offres reçues »).
CREATE POLICY visit_offer_nurse_select ON visit_offer
    FOR SELECT TO nubia_app
    USING (nurse_id = nullif(current_setting('app.current_nurse_id', true), '')::uuid);
CREATE POLICY visit_offer_seed_all ON visit_offer
    TO nubia_seed USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- Fan-out : offre la demande à N infirmières proches et passe requested→offered.
-- SECURITY DEFINER (bypass RLS) car insère des lignes pour d'AUTRES tenants.
-- Retour : 'offered' (ok) | statut courant (si déjà hors 'requested') | 'not_found'.
-- ---------------------------------------------------------------------------
CREATE FUNCTION offer_visit_to_nurses(
    p_request_id uuid,
    p_nurse_ids  uuid[],
    p_ttl        interval DEFAULT interval '5 minutes'
) RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
  SET search_path = public
AS $$
DECLARE
  cur_status text;
BEGIN
  SELECT status INTO cur_status FROM visit_request WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'not_found'; END IF;
  IF cur_status <> 'requested' THEN RETURN cur_status; END IF;

  INSERT INTO visit_offer (visit_request_id, nurse_id, expires_at)
    SELECT p_request_id, n, now() + p_ttl FROM unnest(p_nurse_ids) AS n
    ON CONFLICT (visit_request_id, nurse_id) DO NOTHING;

  UPDATE visit_request
    SET status = 'offered', offered_at = now(), updated_at = now()
    WHERE id = p_request_id;
  RETURN 'offered';
END;
$$;

-- ---------------------------------------------------------------------------
-- Accept : premier·ère infirmière à réclamer une demande offerte gagne.
-- Verrou de ligne = sérialise les accepts concurrents. Exige une offre pending
-- pour cette infirmière. Marque les offres sœurs 'expired'.
-- Retour : 'accepted' | statut courant (409) | 'no_offer' | 'not_found'.
-- ---------------------------------------------------------------------------
CREATE FUNCTION claim_visit(
    p_request_id uuid,
    p_nurse_id   uuid
) RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
  SET search_path = public
AS $$
DECLARE
  cur_status text;
  has_offer  boolean;
BEGIN
  SELECT status INTO cur_status FROM visit_request WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN 'not_found'; END IF;
  IF cur_status <> 'offered' THEN RETURN cur_status; END IF;

  SELECT EXISTS (
    SELECT 1 FROM visit_offer
    WHERE visit_request_id = p_request_id AND nurse_id = p_nurse_id AND status = 'pending'
  ) INTO has_offer;
  IF NOT has_offer THEN RETURN 'no_offer'; END IF;

  UPDATE visit_request
    SET nurse_id = p_nurse_id, status = 'accepted', accepted_at = now(), updated_at = now()
    WHERE id = p_request_id;

  UPDATE visit_offer SET status = 'accepted', responded_at = now()
    WHERE visit_request_id = p_request_id AND nurse_id = p_nurse_id;
  UPDATE visit_offer SET status = 'expired', responded_at = now()
    WHERE visit_request_id = p_request_id AND nurse_id <> p_nurse_id AND status = 'pending';
  RETURN 'accepted';
END;
$$;

-- Refuse une offre pour une infirmière (retire la demande de sa file). Écrit
-- visit_offer (réservé au SECURITY DEFINER). Retour : 'declined' | 'not_found'.
CREATE FUNCTION decline_visit_offer(
    p_request_id uuid,
    p_nurse_id   uuid
) RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
  SET search_path = public
AS $$
DECLARE
  n integer;
BEGIN
  UPDATE visit_offer SET status = 'declined', responded_at = now()
    WHERE visit_request_id = p_request_id AND nurse_id = p_nurse_id AND status = 'pending';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN RETURN 'not_found'; END IF;
  RETURN 'declined';
END;
$$;

ALTER FUNCTION offer_visit_to_nurses(uuid, uuid[], interval) OWNER TO nubia_owner;
ALTER FUNCTION claim_visit(uuid, uuid) OWNER TO nubia_owner;
ALTER FUNCTION decline_visit_offer(uuid, uuid) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION offer_visit_to_nurses(uuid, uuid[], interval) FROM PUBLIC;
REVOKE ALL ON FUNCTION claim_visit(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION decline_visit_offer(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION offer_visit_to_nurses(uuid, uuid[], interval) TO nubia_app;
GRANT EXECUTE ON FUNCTION claim_visit(uuid, uuid) TO nubia_app;
GRANT EXECUTE ON FUNCTION decline_visit_offer(uuid, uuid) TO nubia_app;

COMMENT ON TABLE visit_request IS
    'Demande de visite infirmière à domicile + machine à états (requested→offered→accepted→en_route→arrived→done). RLS 2 ancres patient/infirmière. Clone de pharmacy_order (0124). Épic app infirmières.';
COMMENT ON TABLE visit_offer IS
    'Offres fan-out d''une demande aux infirmières proches (premier-accepté-gagne, cf. claim_visit). Écrit par SECURITY DEFINER uniquement.';
