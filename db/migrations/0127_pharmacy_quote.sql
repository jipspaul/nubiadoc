-- 0127_pharmacy_quote.sql
-- Devis d'officine (lot B7, épic #3323) — table dédiée, volontairement
-- distincte du devis dentaire `quote` (CCAM/AMO/AMC, eIDAS, immutabilité
-- signée) : un devis d'officine est une liste de produits avec prix TTC.
-- Deux ancres RLS : la pharmacie (GUC app.current_pharmacy_id, cycle complet)
-- et le patient (GUC app.patient_account_id, lecture + décision sur un devis
-- envoyé). items jsonb [{label, qty, unit_price_cents}] — montants en
-- centimes (docs/12 §1.1), jamais de donnée de santé.
-- Cycle : draft → sent → accepted|refused (+ expired, posé par un job).
-- Issue : #3312

CREATE TABLE pharmacy_quote (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_id          UUID        NOT NULL REFERENCES pharmacy(id),
    patient_account_id   UUID        NOT NULL REFERENCES patient_account(id),
    order_id             UUID        REFERENCES pharmacy_order(id),
    pharmacy_name        TEXT        NOT NULL,
    patient_display_name TEXT        NOT NULL,
    items                JSONB       NOT NULL DEFAULT '[]',
    total_cents          BIGINT      NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
    currency             CHAR(3)     NOT NULL DEFAULT 'EUR',
    status               TEXT        NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'sent', 'accepted', 'refused', 'expired')),
    sent_at              TIMESTAMPTZ,
    decided_at           TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_pharmacy_quote_pharmacy_status ON pharmacy_quote (pharmacy_id, status);
CREATE INDEX idx_pharmacy_quote_account ON pharmacy_quote (patient_account_id);

REVOKE ALL ON pharmacy_quote FROM nubia_app;
GRANT SELECT, INSERT, UPDATE ON pharmacy_quote TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON pharmacy_quote TO nubia_seed;

ALTER TABLE pharmacy_quote ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_quote FORCE ROW LEVEL SECURITY;

-- Pharmacie : cycle complet sur ses devis — mais ne peut pas forger la
-- décision du patient (WITH CHECK).
CREATE POLICY pharmacy_quote_pharmacy_select ON pharmacy_quote
    FOR SELECT TO nubia_app
    USING (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid);
CREATE POLICY pharmacy_quote_pharmacy_insert ON pharmacy_quote
    FOR INSERT TO nubia_app
    WITH CHECK (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid);
CREATE POLICY pharmacy_quote_pharmacy_update ON pharmacy_quote
    FOR UPDATE TO nubia_app
    USING (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid)
    WITH CHECK (
        pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid
        AND status NOT IN ('accepted', 'refused')
    );

-- Patient : lecture des devis envoyés (jamais les brouillons) + décision.
CREATE POLICY pharmacy_quote_patient_select ON pharmacy_quote
    FOR SELECT TO nubia_app
    USING (
        patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        AND status <> 'draft'
    );
CREATE POLICY pharmacy_quote_patient_update ON pharmacy_quote
    FOR UPDATE TO nubia_app
    USING (
        patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        AND status = 'sent'
    )
    WITH CHECK (
        patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        AND status IN ('accepted', 'refused')
    );

CREATE POLICY pharmacy_quote_seed_all ON pharmacy_quote
    TO nubia_seed USING (true) WITH CHECK (true);

COMMENT ON TABLE pharmacy_quote IS
    'Devis d''officine (produits, prix TTC en centimes) — distinct du devis dentaire quote. Deux ancres RLS (pharmacie / patient). Cycle draft → sent → accepted|refused (+ expired). Réf. épic #3323.';
