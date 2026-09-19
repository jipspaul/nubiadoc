-- 0275_create_invoice_reminder.sql
-- Trace des relances patient sur facture impayée, déclenchées manuellement
-- par le cabinet (#7206). "Facture" = devis `signed`, même terminologie que
-- `patient_alerts.rs` (`kind: "unpaid_invoice"`) : il n'existe pas de table
-- `invoice` distincte dans ce dépôt.
--
-- Une ligne par canal effectivement délivré (in-app+push -> 'push',
-- e-mail -> 'email') plutôt qu'une colonne multi-valeurs : le garde-fou
-- applicatif "1 relance / 7 jours / facture" (POST /v1/invoices/:id/reminder)
-- lit juste l'existence d'une ligne récente, peu importe le canal.
--
-- FK composite (invoice_id, cabinet_id) -> quote (id, cabinet_id) : PostgreSQL
-- fait bypasser la RLS aux vérifications d'intégrité référentielle (FK) même
-- sous FORCE ROW LEVEL SECURITY (#4137/migration 0190) — même pattern que
-- quote_signature_composite_fk (migration 0213) / cabinet_task (0273).
-- `quote_id_cabinet_uniq UNIQUE (id, cabinet_id)` existe depuis la 0213.

CREATE TABLE invoice_reminder (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id uuid        NOT NULL,
    cabinet_id uuid        NOT NULL REFERENCES cabinet(id),
    sent_at    timestamptz NOT NULL DEFAULT now(),
    channel    text        NOT NULL CHECK (channel IN ('push', 'email')),
    sent_by    uuid        NOT NULL REFERENCES app_user(id),
    FOREIGN KEY (invoice_id, cabinet_id) REFERENCES quote (id, cabinet_id)
);

-- Index tenant-first : garde-fou anti-spam (dernière relance d'une facture).
CREATE INDEX idx_invoice_reminder_invoice_sent
    ON invoice_reminder (invoice_id, sent_at DESC);

GRANT SELECT, INSERT, UPDATE, DELETE ON invoice_reminder TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON invoice_reminder TO nubia_seed;

ALTER TABLE invoice_reminder ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoice_reminder FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON invoice_reminder
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE invoice_reminder IS
    'Trace des relances patient sur facture (devis signé) impayée, déclenchées manuellement par le cabinet. Table tenant (cabinet_id). RLS fail-closed. Issue #7206.';
