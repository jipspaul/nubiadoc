-- 0207_quote_relance.sql
-- Historique de relance des devis en attente de signature (#4126) : le
-- worker `quote_relance_dispatch` notifie le patient à J+3/J+7 si son devis
-- reste `sent`. Cette table trace ce qui a déjà été envoyé (évite les
-- doublons à chaque passage du worker) et expose l'historique au cabinet.
--
-- UNIQUE(quote_id, milestone) : un même jalon (j3 ou j7) ne peut être
-- enregistré qu'une fois par devis — le worker s'appuie dessus (NOT EXISTS)
-- plutôt que sur un flag booléen sur `quote`, pour garder l'historique
-- complet (2 lignes par devis relancé jusqu'au bout) au lieu d'un simple
-- "dernière relance".

CREATE TABLE quote_relance (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id  uuid        NOT NULL REFERENCES cabinet(id),
    quote_id    uuid        NOT NULL REFERENCES quote(id),
    milestone   text        NOT NULL CHECK (milestone IN ('j3', 'j7')),
    sent_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (quote_id, milestone)
);

CREATE INDEX idx_quote_relance_quote ON quote_relance (quote_id);

ALTER TABLE quote_relance ENABLE ROW LEVEL SECURITY;
ALTER TABLE quote_relance FORCE ROW LEVEL SECURITY;

CREATE POLICY quote_relance_tenant_isolation ON quote_relance
    FOR ALL
    USING  (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON quote_relance TO nubia_app;

COMMENT ON TABLE quote_relance IS
    'Historique des relances J+3/J+7 sur les devis en attente de signature (#4126). Un jalon par devis maximum (UNIQUE quote_id, milestone).';
