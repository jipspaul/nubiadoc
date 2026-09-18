-- 0272_slot_hold_expired_release.sql
-- #6992 / #6840 : un hold de créneau abandonné stérilise le créneau
-- DÉFINITIVEMENT. Le hold expire bien à `slot_holds.expires_at` (10 min,
-- 0255/0256), mais rien ne repasse le créneau en `open` : la seule
-- libération existante (0141, #3606) est PARESSEUSE, interne à
-- `claim_and_hold_slot`, donc atteignable uniquement par un nouveau
-- `POST /v1/slots/:id/hold` sur ce créneau précis. Or les listings publics
-- (`/v1/search/slots`, `/v1/providers/:id/availability`) — et les policies
-- RLS de lecture publique `slot_public_read` (0059) /
-- `availability_slot_patient_read` (0117) — ne montrent que `status='open'`
-- sans jamais consulter `slot_holds.expires_at`. Un créneau `held`-expiré est
-- donc indécouvrable, donc plus jamais candidat au hold qui l'aurait libéré.
-- Chaque tunnel abandonné (cas nominal) retire un créneau du catalogue.
--
-- Deux volets complémentaires :
--
-- 1. `slot_hold_expired(p_slot_id)` + policy `slot_public_read_expired_hold` :
--    la lecture publique traite comme réservable un créneau `held` dont le
--    hold est expiré — filtre `expires_at` DANS LA REQUÊTE (marketplace.rs,
--    `SLOT_BOOKABLE_CLAUSE`), correct dès la première seconde après
--    `expires_at`, sans dépendre d'un reaper. Fonction SECURITY DEFINER
--    (même pattern que `provider_unavailable_at`, 0220) : `slot_holds` est
--    sous FORCE RLS scopée cabinet (0110) et les routes de recherche sont
--    publiques (aucun GUC) — un `EXISTS` direct ne verrait jamais aucune
--    ligne. Un `held` SANS ligne `slot_holds` reste invisible (état non
--    produit par l'application : seul `claim_and_hold_slot` pose `held`, et
--    toujours avec son hold ; le PATCH cabinet n'accepte que open/blocked).
--
-- 2. `release_expired_slot_holds()` : reaper appelé périodiquement par
--    l'API (`api/src/slot_hold_expiry.rs`, même pattern tokio::spawn que
--    `expire_stale_visit_offers`, 0236) — purge les holds expirés et repasse
--    les créneaux `held` en `open`, pour que l'état en base (agenda cabinet,
--    interop FHIR Slot) redevienne cohérent au lieu de rester `held` à vie.
--    Ordre de verrouillage IDENTIQUE à `claim_and_hold_slot` (créneau
--    FOR UPDATE d'abord, puis hold) : aucun interblocage possible avec un
--    hold/renouvellement (#6509) concurrent, et l'expiration est re-vérifiée
--    sous verrou (un hold renouvelé entre-temps n'est pas purgé).
-- Issue : #6992, #6840

-- ---------------------------------------------------------------------------
-- 1. Lecture : hold expiré = créneau réservable
-- ---------------------------------------------------------------------------
CREATE FUNCTION slot_hold_expired(p_slot_id uuid)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET row_security = off
AS $$
  SELECT EXISTS (
    SELECT 1 FROM slot_holds h
    WHERE h.slot_id = p_slot_id
      AND h.expires_at <= now()
  );
$$;

ALTER FUNCTION slot_hold_expired(uuid) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION slot_hold_expired(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION slot_hold_expired(uuid) TO nubia_app;

-- Policy permissive additionnelle (OR avec slot_public_read /
-- availability_slot_patient_read) : sans elle, le filtre applicatif ne
-- verrait jamais la ligne `held` (RLS fail-closed sur status='open').
CREATE POLICY slot_public_read_expired_hold ON availability_slot
  FOR SELECT
  USING (status = 'held' AND slot_hold_expired(id));

-- ---------------------------------------------------------------------------
-- 2. Reaper : purge des holds expirés + retour des créneaux en open
-- ---------------------------------------------------------------------------
CREATE FUNCTION release_expired_slot_holds()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
AS $$
DECLARE
  released integer := 0;
  r record;
BEGIN
  FOR r IN
    SELECT h.slot_id FROM slot_holds h WHERE h.expires_at <= now()
  LOOP
    -- Même ordre de verrouillage que claim_and_hold_slot : créneau d'abord.
    PERFORM 1 FROM availability_slot WHERE id = r.slot_id FOR UPDATE;
    -- Re-vérifié sous verrou : renouvelé (#6509) ou consommé (bookings)
    -- entre-temps → rien à purger.
    DELETE FROM slot_holds WHERE slot_id = r.slot_id AND expires_at <= now();
    IF FOUND THEN
      UPDATE availability_slot
        SET status = 'open', updated_at = now()
        WHERE id = r.slot_id AND status = 'held';
      released := released + 1;
    END IF;
  END LOOP;
  RETURN released;
END;
$$;

ALTER FUNCTION release_expired_slot_holds() OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION release_expired_slot_holds() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION release_expired_slot_holds() TO nubia_app;
