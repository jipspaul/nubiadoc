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

-- availability_slot : nubia_app SELECT non restreint au statut 'open' pour le mécanisme de hold.
-- (La policy slot_public_read limite la lecture à status='open' pour les routes publiques,
-- mais le handler POST /v1/slots/:id/hold doit pouvoir distinguer "inexistant" de "déjà held".)
