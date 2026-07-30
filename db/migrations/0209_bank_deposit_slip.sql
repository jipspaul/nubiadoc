-- 0209_bank_deposit_slip.sql
-- Bordereau de remise en banque pour les chèques encaissés (#4128).
--
-- `bank_deposit_slip` : un bordereau généré par appel (immutable, jamais
-- modifié après coup — mirror de `cash_register_closing`, migration 0165).
-- `bank_deposit_slip_payment` : table de liaison qui marque chaque paiement
-- comme déjà inclus dans un bordereau — UNIQUE(payment_id) empêche qu'un
-- même chèque se retrouve sur deux bordereaux (mirror de `quote_relance`,
-- migration 0207 : marqueur par ligne plutôt qu'un flag sur `payment`, pour
-- ne pas élargir une table déjà multi-usage).

CREATE TABLE bank_deposit_slip (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id          uuid        NOT NULL REFERENCES cabinet(id),
    period_from         date        NOT NULL,
    period_to           date        NOT NULL,
    total_amount_cents  bigint      NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE bank_deposit_slip ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_deposit_slip FORCE ROW LEVEL SECURITY;

CREATE POLICY bank_deposit_slip_tenant_isolation ON bank_deposit_slip
    FOR ALL
    USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- Immutable une fois créé : ni UPDATE ni DELETE (mirror cash_register_closing).
GRANT SELECT, INSERT ON bank_deposit_slip TO nubia_app;

COMMENT ON TABLE bank_deposit_slip IS
    'Bordereau de remise en banque des chèques encaissés (#4128). Immutable après création.';

CREATE TABLE bank_deposit_slip_payment (
    cabinet_id  uuid NOT NULL REFERENCES cabinet(id),
    slip_id     uuid NOT NULL REFERENCES bank_deposit_slip(id),
    payment_id  uuid NOT NULL REFERENCES payment(id),
    PRIMARY KEY (slip_id, payment_id),
    UNIQUE (payment_id)
);

CREATE INDEX idx_bank_deposit_slip_payment_slip ON bank_deposit_slip_payment (slip_id);

ALTER TABLE bank_deposit_slip_payment ENABLE ROW LEVEL SECURITY;
ALTER TABLE bank_deposit_slip_payment FORCE ROW LEVEL SECURITY;

CREATE POLICY bank_deposit_slip_payment_tenant_isolation ON bank_deposit_slip_payment
    FOR ALL
    USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT ON bank_deposit_slip_payment TO nubia_app;

COMMENT ON TABLE bank_deposit_slip_payment IS
    'Lien paiement -> bordereau (#4128). UNIQUE(payment_id) : un chèque ne peut figurer que sur un seul bordereau.';
