-- 0193_create_lab_work_order.sql
-- Suivi des bons de travaux prothétiques (#4147) : aucune trace de suivi des
-- travaux de laboratoire prothétique dans le schéma (absent de
-- db/migrations/ et docs/05).
--
-- lab_work_order : un bon de travail envoyé à un laboratoire prothétique,
-- optionnellement rattaché à une ligne de devis (quote_item_id) et/ou au
-- rendez-vous de pose (appointment_id). purchase_price_cents est
-- OBLIGATOIRE (déclaration du prix d'achat, §N du référentiel) — pas de bon
-- de travail sans coût déclaré, condition nécessaire au calcul de marge.
--
-- FK COMPOSITES (patient_id, cabinet_id) / (quote_item_id, cabinet_id) /
-- (appointment_id, cabinet_id) plutôt que des FK simples sur l'id seul :
-- PostgreSQL fait bypasser la RLS aux vérifications d'intégrité
-- référentielle (FK/UNIQUE/PK) même sous FORCE ROW LEVEL SECURITY — cf.
-- #4137/migration 0190. patient/appointment/quote_item n'ont pas encore de
-- UNIQUE (id, cabinet_id) (tables plus anciennes, migrations 0003/0005/0006)
-- — ajouté ici pour chacune, fix standard : un mismatch de cabinet_id ne
-- correspond à aucune ligne de l'index unique, la FK échoue en 23503
-- indépendamment de la RLS.

ALTER TABLE patient
    ADD CONSTRAINT patient_id_cabinet_uniq UNIQUE (id, cabinet_id);
ALTER TABLE appointment
    ADD CONSTRAINT appointment_id_cabinet_uniq UNIQUE (id, cabinet_id);
ALTER TABLE quote_item
    ADD CONSTRAINT quote_item_id_cabinet_uniq UNIQUE (id, cabinet_id);

CREATE TABLE lab_work_order (
    id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id            uuid        NOT NULL REFERENCES cabinet(id),
    patient_id            uuid        NOT NULL,
    quote_item_id         uuid,
    appointment_id        uuid,
    lab_name              text        NOT NULL,
    purchase_price_cents  integer     NOT NULL CHECK (purchase_price_cents >= 0),
    status                text        NOT NULL DEFAULT 'sent'
                                       CHECK (status IN ('sent', 'try_in', 'returned', 'fitted')),
    sent_at               timestamptz NOT NULL DEFAULT now(),
    expected_return_at    timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (patient_id, cabinet_id)
        REFERENCES patient (id, cabinet_id),
    FOREIGN KEY (quote_item_id, cabinet_id)
        REFERENCES quote_item (id, cabinet_id),
    FOREIGN KEY (appointment_id, cabinet_id)
        REFERENCES appointment (id, cabinet_id)
);

CREATE INDEX idx_lab_work_order_cabinet
    ON lab_work_order (cabinet_id);
CREATE INDEX idx_lab_work_order_patient
    ON lab_work_order (patient_id);
CREATE INDEX idx_lab_work_order_quote_item
    ON lab_work_order (quote_item_id)
    WHERE quote_item_id IS NOT NULL;
CREATE INDEX idx_lab_work_order_appointment
    ON lab_work_order (appointment_id)
    WHERE appointment_id IS NOT NULL;

-- RLS tenant (fail-closed : GUC absent → 0 ligne).
ALTER TABLE lab_work_order ENABLE ROW LEVEL SECURITY;
ALTER TABLE lab_work_order FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON lab_work_order
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON lab_work_order TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON lab_work_order TO nubia_seed;

COMMENT ON TABLE lab_work_order IS
    'Bon de travail prothétique envoyé à un laboratoire (statut sent/try_in/returned/fitted), prix d''achat obligatoire. #4147.';
