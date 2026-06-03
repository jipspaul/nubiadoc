-- 0008_audit_consent.sql
-- Audit append-only (partitionné par mois) & consentements. Réf. : docs/05 §6, db/README §7.
-- Append-only GARANTI PAR PRIVILÈGE : nubia_app n'a que INSERT (pas d'UPDATE/DELETE).
-- RLS (cabinet_id) posée en 0011 ; la policy WITH CHECK empêche l'app de forger une
-- entrée pour un autre cabinet.

CREATE TABLE audit_log (
  id          bigint GENERATED ALWAYS AS IDENTITY,
  cabinet_id  uuid NOT NULL,
  actor_id    uuid,
  actor_role  text,
  action      text NOT NULL,        -- read_record, update_quote, sign, login, purge...
  entity      text NOT NULL,
  entity_id   uuid,
  metadata    jsonb NOT NULL DEFAULT '{}',   -- jamais de PII en clair
  occurred_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (id, occurred_at)              -- la clé de partition doit être dans la PK
) PARTITION BY RANGE (occurred_at);

-- Partitions mensuelles. Le job apalis crée les partitions futures (db/README §6, §7) ;
-- on amorce la fenêtre démo + une partition DEFAULT fail-safe (aucun INSERT ne casse).
CREATE TABLE audit_log_2026_05 PARTITION OF audit_log
  FOR VALUES FROM ('2026-05-01 00:00:00+00') TO ('2026-06-01 00:00:00+00');
CREATE TABLE audit_log_2026_06 PARTITION OF audit_log
  FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');
CREATE TABLE audit_log_2026_07 PARTITION OF audit_log
  FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');
CREATE TABLE audit_log_default PARTITION OF audit_log DEFAULT;

-- Append-only par privilège : on retire tout puis on ne rend que INSERT à l'app.
-- (Les droits par défaut de 0001 auraient sinon donné UPDATE/DELETE/SELECT.)
REVOKE ALL ON audit_log FROM nubia_app, nubia_seed;
REVOKE ALL ON audit_log_2026_05, audit_log_2026_06, audit_log_2026_07, audit_log_default
  FROM nubia_app, nubia_seed;
GRANT INSERT ON audit_log TO nubia_app;   -- routage vers les partitions via le parent

CREATE TABLE consent_record (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id uuid NOT NULL REFERENCES cabinet(id),
  patient_id uuid NOT NULL REFERENCES patient(id),
  purpose    text NOT NULL,        -- soins, ia_scribe (post-MVP), marketing, partage_confrere
  granted    boolean NOT NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,          -- révocable
  evidence   jsonb NOT NULL DEFAULT '{}'
);
