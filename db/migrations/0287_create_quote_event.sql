-- 0287_create_quote_event.sql
-- Journal d'un devis : timeline patient-lisible des événements (créé,
-- envoyé, consulté par le patient, relancé, signé, refusé, message).
-- `audit_log` (0008) est un journal technique cabinet-only (actor_role,
-- purge CNIL...), pas conçu pour être exposé tel quel au patient. Ici :
-- table dédiée, lue par le patient sur ses propres devis (#7177).
--
-- FK composite (quote_id, cabinet_id) -> quote (id, cabinet_id) : PostgreSQL
-- fait bypasser la RLS aux vérifications d'intégrité référentielle (FK) même
-- sous FORCE ROW LEVEL SECURITY (#4137/migration 0190) — même pattern que
-- invoice_reminder (0275) / quote_signature_composite_fk (0213). La
-- contrainte `quote_id_cabinet_uniq UNIQUE (id, cabinet_id)` existe depuis
-- la 0213.
--
-- actor_id polymorphe (pas de FK, même choix qu'audit_log.actor_id en 0008) :
-- référence app_user si actor_kind = 'cabinet', patient si 'patient', NULL
-- si 'system' (ex. expiration automatique du devis par le worker).
--
-- Append-only : nubia_app n'a que SELECT + INSERT (pas d'UPDATE/DELETE), un
-- événement de journal ne se corrige pas, il s'annule par un nouvel
-- événement. REVOKE puis GRANT explicites nécessaires : ALTER DEFAULT
-- PRIVILEGES (0001) accorde SELECT/INSERT/UPDATE/DELETE par défaut à
-- nubia_app sur toute nouvelle table — même pattern que audit_log (0008).

CREATE TABLE quote_event (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    quote_id   uuid        NOT NULL,
    cabinet_id uuid        NOT NULL REFERENCES cabinet(id),
    kind       text        NOT NULL
                CHECK (kind IN ('created', 'sent', 'viewed', 'reminded', 'signed', 'refused', 'message')),
    at         timestamptz NOT NULL DEFAULT now(),
    actor_kind text        NOT NULL CHECK (actor_kind IN ('cabinet', 'patient', 'system')),
    actor_id   uuid,
    meta       jsonb       NOT NULL DEFAULT '{}',
    FOREIGN KEY (quote_id, cabinet_id) REFERENCES quote (id, cabinet_id)
);

-- Index tenant-first : timeline d'un devis triée chronologiquement.
CREATE INDEX idx_quote_event_quote_at
    ON quote_event (quote_id, at);

REVOKE ALL ON quote_event FROM nubia_app;
GRANT SELECT, INSERT ON quote_event TO nubia_app;

ALTER TABLE quote_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE quote_event FORCE ROW LEVEL SECURITY;

-- Cabinet : isolation tenant standard.
CREATE POLICY tenant_isolation ON quote_event
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- Patient : lecture seule de la timeline de ses propres devis, mêmes
-- conditions que quote_patient_read (0134) — un devis 'draft' n'est jamais
-- exposé au patient, donc ni ses événements.
CREATE POLICY quote_event_patient_read ON quote_event
    FOR SELECT
    TO nubia_app
    USING (
        quote_id IN (
            SELECT id FROM quote
            WHERE status <> 'draft'
              AND patient_id IN (
                  SELECT id FROM patient
                  WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
              )
        )
    );

COMMENT ON TABLE quote_event IS 'Journal des événements d''un devis (timeline patient-lisible). Table tenant (cabinet_id). RLS fail-closed. Issue #7177.';
