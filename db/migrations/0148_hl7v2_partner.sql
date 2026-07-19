-- 0148_hl7v2_partner.sql
-- Interop HL7 v2 / MLLP (lot B6, suite des lots B1-B4 : parseur + codec MLLP,
-- crate `integrations-hl7v2`, sans persistance). Ici : le registre des
-- partenaires EAI/laboratoires qui parlent HL7v2 en mTLS.
--
-- ⚠️ Sans rapport avec `interop_client` (lot A1, autre branche) : ce dernier
-- authentifie des consommateurs REST via OAuth2 client-credentials. Un
-- partenaire HL7v2 est identifié par l'empreinte SHA-256 de son certificat
-- client mTLS — mécanisme distinct, d'où le préfixe `hl7v2_` pour éviter
-- toute confusion une fois les deux lots réunis dans le même schéma.
--
-- Trois tables :
--   hl7v2_partner              — registre PLATEFORME (comme patient_account,
--                                 0009) : un partenaire EAI peut parler à
--                                 plusieurs cabinets, donc pas de cabinet_id,
--                                 pas de RLS cabinet.
--   hl7v2_partner_facility_map — TENANT-SCOPED (cabinet_id) : associe un
--                                 partenaire à un cabinet pour un couple
--                                 (MSH-4 sending facility, MSH-6 receiving
--                                 facility) donné. RLS fail-closed, pattern
--                                 stock_request (0125).
--   hl7v2_message_log          — dédup/idempotence PLATEFORME (comme
--                                 hl7v2_partner : le dispatch doit détecter un
--                                 message rejoué juste après résolution du
--                                 partenaire, AVANT résolution du cabinet via
--                                 hl7v2_partner_facility_map — donc pas de
--                                 cabinet_id disponible à ce stade, pas de RLS
--                                 cabinet possible).
--
-- Deux fonctions SECURITY DEFINER (pattern payment_find_by_provider_ref,
-- 0103) pour les lookups pré-tenant du dispatch :
--   hl7v2_partner_find_by_fingerprint(text) — résout le partenaire depuis
--     l'empreinte du certificat mTLS présenté à la connexion MLLP (avant tout
--     GUC cabinet, l'empreinte seule n'impliquant pas un cabinet unique).
--   hl7v2_message_log_check_and_insert(uuid, text) — insertion atomique
--     (INSERT ... ON CONFLICT DO NOTHING RETURNING) : évite la race d'un
--     SELECT-puis-INSERT si deux livraisons quasi simultanées du même message
--     arrivent en parallèle (deux connexions MLLP concurrentes du partenaire).

-- ---------------------------------------------------------------------------
-- hl7v2_partner — registre plateforme des partenaires HL7v2/EAI.
-- ---------------------------------------------------------------------------
CREATE TABLE hl7v2_partner (
  id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name            text        NOT NULL,
  -- Empreinte SHA-256 du certificat client mTLS, encodée en hex MINUSCULE
  -- (64 caractères [0-9a-f]) — format produit par `openssl x509 -fingerprint
  -- -sha256 -noout` puis normalisé lowercase côté handshake TLS (lot B5).
  cert_fingerprint_sha256 text        NOT NULL UNIQUE,
  status                  text        NOT NULL DEFAULT 'active'
                            CHECK (status IN ('active', 'revoked')),
  created_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hl7v2_partner_fingerprint_format
    CHECK (cert_fingerprint_sha256 ~ '^[0-9a-f]{64}$')
);

COMMENT ON TABLE hl7v2_partner IS
  'Registre plateforme des partenaires HL7v2/EAI identifiés par empreinte de certificat mTLS. Pas de cabinet_id : un partenaire peut parler à plusieurs cabinets (cf. hl7v2_partner_facility_map). Réf. lot B6.';
COMMENT ON COLUMN hl7v2_partner.cert_fingerprint_sha256 IS
  'SHA-256 du certificat client mTLS, hex-encodé en minuscules (64 car. [0-9a-f]).';

GRANT SELECT, INSERT, UPDATE, DELETE ON hl7v2_partner TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON hl7v2_partner TO nubia_seed;

-- ---------------------------------------------------------------------------
-- hl7v2_partner_facility_map — tenant-scoped : partenaire × cabinet pour un
-- couple (sending facility, receiving facility) MSH-4/MSH-6 donné.
-- ---------------------------------------------------------------------------
CREATE TABLE hl7v2_partner_facility_map (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id        uuid        NOT NULL REFERENCES hl7v2_partner(id),
  -- MSH-4 attendu de ce partenaire pour ce cabinet.
  sending_facility   text       NOT NULL,
  -- MSH-6 attendu de ce partenaire pour ce cabinet.
  receiving_facility text       NOT NULL,
  cabinet_id         uuid       NOT NULL REFERENCES cabinet(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (partner_id, sending_facility, receiving_facility)
);

CREATE INDEX idx_hl7v2_partner_facility_map_cabinet ON hl7v2_partner_facility_map (cabinet_id);

REVOKE ALL ON hl7v2_partner_facility_map FROM nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON hl7v2_partner_facility_map TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON hl7v2_partner_facility_map TO nubia_seed;

ALTER TABLE hl7v2_partner_facility_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE hl7v2_partner_facility_map FORCE ROW LEVEL SECURITY;

CREATE POLICY hl7v2_partner_facility_map_cabinet ON hl7v2_partner_facility_map
  FOR ALL
  TO nubia_app
  USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
  WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY hl7v2_partner_facility_map_seed_all ON hl7v2_partner_facility_map
  TO nubia_seed USING (true) WITH CHECK (true);

COMMENT ON TABLE hl7v2_partner_facility_map IS
  'Association tenant-scoped partenaire HL7v2 <-> cabinet pour un couple (MSH-4, MSH-6) donné. RLS fail-closed sur cabinet_id. Réf. lot B6.';

-- ---------------------------------------------------------------------------
-- hl7v2_message_log — dédup/idempotence plateforme (MSH-10), pré-tenant.
-- ---------------------------------------------------------------------------
CREATE TABLE hl7v2_message_log (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id        uuid        NOT NULL REFERENCES hl7v2_partner(id),
  -- MSH-10 : identifiant de contrôle du message, unique par partenaire.
  message_control_id text       NOT NULL,
  received_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (partner_id, message_control_id)
);

CREATE INDEX idx_hl7v2_message_log_partner ON hl7v2_message_log (partner_id, received_at);

COMMENT ON TABLE hl7v2_message_log IS
  'Journal de dédup HL7v2 par (partner_id, MSH-10). Plateforme (pas de cabinet_id) : consulté par le dispatch avant résolution du cabinet via hl7v2_partner_facility_map. Réf. lot B6.';

-- Append-only côté app (comme audit_log, 0008) : nubia_app ne fait jamais
-- d'UPDATE/DELETE directement — le seul chemin d'écriture passe par la
-- fonction SECURITY DEFINER ci-dessous (INSERT ... ON CONFLICT atomique).
REVOKE ALL ON hl7v2_message_log FROM nubia_app;
GRANT SELECT, INSERT ON hl7v2_message_log TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON hl7v2_message_log TO nubia_seed;

-- ---------------------------------------------------------------------------
-- hl7v2_partner_find_by_fingerprint — lookup pré-tenant par empreinte mTLS.
-- SECURITY DEFINER : la table plateforme n'a pas de RLS, mais on garde le
-- même pattern que payment_find_by_provider_ref (0103) pour borner l'accès à
-- une lecture précise plutôt qu'un GRANT SELECT large côté handler.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hl7v2_partner_find_by_fingerprint(p_cert_fingerprint_sha256 text)
    RETURNS hl7v2_partner
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT *
    FROM hl7v2_partner
    WHERE cert_fingerprint_sha256 = p_cert_fingerprint_sha256
      AND status = 'active'
    LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION hl7v2_partner_find_by_fingerprint(text) TO nubia_app;

-- ---------------------------------------------------------------------------
-- hl7v2_message_log_check_and_insert — insertion atomique anti-race.
-- Retourne true si le message est FRAIS (jamais vu, ligne insérée), false
-- s'il s'agit d'un doublon (conflit sur (partner_id, message_control_id)).
-- L'atomicité de l'INSERT ... ON CONFLICT évite qu'un SELECT-puis-INSERT
-- laisse passer deux livraisons quasi simultanées du même message.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hl7v2_message_log_check_and_insert(
    p_partner_id uuid,
    p_control_id text
)
    RETURNS boolean
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path = public
AS $$
    WITH ins AS (
        INSERT INTO hl7v2_message_log (partner_id, message_control_id)
        VALUES (p_partner_id, p_control_id)
        ON CONFLICT (partner_id, message_control_id) DO NOTHING
        RETURNING id
    )
    SELECT EXISTS (SELECT 1 FROM ins);
$$;

GRANT EXECUTE ON FUNCTION hl7v2_message_log_check_and_insert(uuid, text) TO nubia_app;
