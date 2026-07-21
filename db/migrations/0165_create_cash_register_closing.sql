-- 0165_create_cash_register_closing.sql
-- Clôture de caisse journalière (#4071). Aucune notion de caisse n'existait
-- dans le schéma : impossible de produire un total encaissé par mode de
-- paiement sur une journée, obligatoire en centre de santé et attendu en
-- cabinet libéral.
-- Table tenant (cabinet_id), même pattern RLS que patient_tag (migration 0158).
-- `totals_by_method` (jsonb) plutôt qu'une colonne par méthode : le nombre
-- de méthodes évolue (cash/check/bank_transfer ajoutées en #4070, méthodes
-- carte/SEPA existantes) sans nécessiter de migration à chaque ajout.
-- Alimentée par une requête d'agrégation sur `payment` (paiements
-- `status='paid'` du jour), pas par une saisie manuelle.

CREATE TABLE cash_register_closing (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id        UUID        NOT NULL REFERENCES cabinet(id),
    closing_date      DATE        NOT NULL,
    totals_by_method  JSONB       NOT NULL DEFAULT '{}',
    total_amount      NUMERIC(12,2) NOT NULL DEFAULT 0,
    closed_by         UUID        NOT NULL REFERENCES app_user(id),
    closed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Une seule clôture par cabinet et par jour : la clôture fige la
    -- journée, une deuxième clôture le même jour serait soit un doublon,
    -- soit une correction qui doit être explicite (hors scope #4071).
    CONSTRAINT cash_register_closing_unique_per_day UNIQUE (cabinet_id, closing_date)
);

-- Index tenant-first : liste des clôtures d'un cabinet, tri chronologique.
CREATE INDEX idx_cash_register_closing_cabinet_date
    ON cash_register_closing (cabinet_id, closing_date DESC);

GRANT SELECT, INSERT ON cash_register_closing TO nubia_app;
GRANT SELECT, INSERT ON cash_register_closing TO nubia_seed;

-- RLS : isolation par cabinet (même pattern que patient_tag, migration 0158).
ALTER TABLE cash_register_closing ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_register_closing FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON cash_register_closing
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE cash_register_closing IS 'Clôture de caisse journalière : totaux encaissés par méthode de paiement, figés à la clôture. Table tenant (cabinet_id). RLS fail-closed. Issue #4071.';
COMMENT ON COLUMN cash_register_closing.totals_by_method IS 'Totaux en centimes par méthode de paiement (cash/check/bank_transfer/card/apple_pay/google_pay/sepa), ex. {"cash": 5000, "card": 12000}.';
