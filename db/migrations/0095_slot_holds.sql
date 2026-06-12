-- 0094_slot_holds.sql
-- Table slot_holds : bloque un créneau 5 min en attente de confirmation.
-- Réf. : issue #1659, docs/12-api-reference.md §E.3.21.
--
-- Un patient peut poser un hold sur un slot open → slot passe en 'held'.
-- Expiration automatique à expires_at (now() + 5 min).
-- Contrainte d'unicité sur slot_id : un seul hold actif par créneau.

CREATE TABLE slot_holds (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slot_id       uuid NOT NULL REFERENCES availability_slot(id),
  user_id       uuid NOT NULL REFERENCES app_user(id),
  hold_token    text NOT NULL,
  expires_at    timestamptz NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT slot_holds_slot_unique UNIQUE (slot_id)
);

-- RLS : pas de tenant_id (table plateforme), accès contrôlé par policy applicative.
ALTER TABLE slot_holds ENABLE ROW LEVEL SECURITY;
ALTER TABLE slot_holds FORCE ROW LEVEL SECURITY;

-- nubia_app : INSERT + SELECT + DELETE (libération du hold à l'expiration ou à la réservation).
CREATE POLICY slot_holds_app ON slot_holds
  FOR ALL TO nubia_app
  USING (true) WITH CHECK (true);

-- nubia_seed : accès complet (données de démo fictives).
CREATE POLICY slot_holds_seed ON slot_holds
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);

-- SECURITY DEFINER : permet au handler hold_slot de claim un slot marketplace
-- SANS s'appuyer sur policy permissive (slot_public_read filter status='open',
-- slot_cabinet_write require cabinet_id=GUC qui bloque les writes marketplace
-- sur les slots à cabinet_id=NULL).
-- Owner = nubia_owner ; SET row_security=off pour bypasser FORCE RLS sur
-- nubia_owner (cf. db/README §3 — nubia_owner sans BYPASSRLS attribute).
-- Returns: status_after ('held' if claim succeeded, current status if not, NULL if slot doesn't exist).
CREATE FUNCTION try_claim_slot(p_slot_id uuid)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET row_security = off
AS $$
DECLARE
  current_status text;
BEGIN
  SELECT status INTO current_status FROM availability_slot WHERE id = p_slot_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NULL;  -- 404
  END IF;
  IF current_status <> 'open' THEN
    RETURN current_status;  -- 409
  END IF;
  UPDATE availability_slot SET status='held' WHERE id = p_slot_id;
  RETURN 'held';  -- 200
END;
$$;
ALTER FUNCTION try_claim_slot(uuid) OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION try_claim_slot(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION try_claim_slot(uuid) TO nubia_app;
