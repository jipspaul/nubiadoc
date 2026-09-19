-- 0278_quote_attachment_information_attestation.sql
-- Pièces jointes de devis et attestation d'information (#7204).
--
-- quote_attachment : rattache un devis à un document déjà stocké (coffre-fort
-- `document`, ex. consentement/ordonnance scanné) OU à un modèle de courrier
-- non encore matérialisé en document (template_ref) — jamais les deux à la
-- fois, ni aucun des deux.
--
-- quote_information_attestation : texte d'attestation d'information remis au
-- patient avant signature du devis, avec trace de signature (signed_at +
-- signature_ref), même esprit que `signature` (0006) mais porté par le devis
-- plutôt qu'un provider de signature électronique externe.
--
-- FK COMPOSITES (quote_id/document_id/patient_id + cabinet_id) plutôt que des
-- FK simples : PostgreSQL fait bypasser la RLS aux vérifications d'intégrité
-- référentielle (FK) même sous FORCE ROW LEVEL SECURITY (#4137/migration
-- 0190) — même pattern que lab_work_order (0193) / pharmacy_order (0210) /
-- quote_signature_composite_fk (0213). Les UNIQUE (id, cabinet_id) requis
-- existent déjà : quote_id_cabinet_uniq (0213), document_id_cabinet_uniq
-- (0210), patient_id_cabinet_uniq (0193).
--
-- RLS : tenant_isolation (cabinet) + lecture patient sur ses propres devis
-- non-brouillon, même pattern que quote_patient_read (0134).

CREATE TABLE quote_attachment (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id   uuid        NOT NULL REFERENCES cabinet(id),
    quote_id     uuid        NOT NULL,
    kind         text        NOT NULL CHECK (kind IN ('consent', 'prescription', 'letter', 'other')),
    document_id  uuid,
    template_ref text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (quote_id, cabinet_id)
        REFERENCES quote (id, cabinet_id),
    FOREIGN KEY (document_id, cabinet_id)
        REFERENCES document (id, cabinet_id),
    CONSTRAINT quote_attachment_source_xor
        CHECK (num_nonnulls(document_id, template_ref) = 1)
);

CREATE INDEX idx_quote_attachment_cabinet_quote
    ON quote_attachment (cabinet_id, quote_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON quote_attachment TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON quote_attachment TO nubia_seed;

ALTER TABLE quote_attachment ENABLE ROW LEVEL SECURITY;
ALTER TABLE quote_attachment FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON quote_attachment
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY quote_attachment_patient_read ON quote_attachment
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

COMMENT ON TABLE quote_attachment IS
    'Pièce jointe d''un devis : document déjà stocké (consentement/ordonnance/courrier) ou modèle de courrier non matérialisé (XOR document_id/template_ref). Table tenant (cabinet_id). RLS fail-closed. Issue #7204.';

CREATE TABLE quote_information_attestation (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id    uuid        NOT NULL REFERENCES cabinet(id),
    quote_id      uuid        NOT NULL,
    patient_id    uuid        NOT NULL,
    body          text        NOT NULL,
    signed_at     timestamptz,
    signature_ref text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (quote_id, cabinet_id)
        REFERENCES quote (id, cabinet_id),
    FOREIGN KEY (patient_id, cabinet_id)
        REFERENCES patient (id, cabinet_id),
    CONSTRAINT quote_information_attestation_body_not_blank
        CHECK (btrim(body) <> '')
);

CREATE INDEX idx_quote_information_attestation_cabinet_quote
    ON quote_information_attestation (cabinet_id, quote_id);
CREATE INDEX idx_quote_information_attestation_patient
    ON quote_information_attestation (patient_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON quote_information_attestation TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON quote_information_attestation TO nubia_seed;

ALTER TABLE quote_information_attestation ENABLE ROW LEVEL SECURITY;
ALTER TABLE quote_information_attestation FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON quote_information_attestation
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY quote_information_attestation_patient_read ON quote_information_attestation
    FOR SELECT
    TO nubia_app
    USING (
        quote_id IN (SELECT id FROM quote WHERE status <> 'draft')
        AND patient_id IN (
            SELECT id FROM patient
            WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        )
    );

COMMENT ON TABLE quote_information_attestation IS
    'Attestation d''information remise au patient avant signature du devis (texte + trace de signature). Table tenant (cabinet_id). RLS fail-closed. Issue #7204.';
