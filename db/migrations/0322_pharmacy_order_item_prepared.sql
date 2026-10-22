-- 0322_pharmacy_order_item_prepared.sql
-- jips/nubiadoc#8340 : la case « sortie des rayons » (#6783) était stockée
-- sur prescription_item, donc sur l'ORDONNANCE — elle survivait au cycle de
-- vie de la commande qui l'avait produite. Un refus pharmacie libère
-- l'ordonnance côté patient (cf. reject_pharmacy_order) : la commande
-- suivante (même pharmacie, voire une AUTRE officine) naissait avec les
-- cases déjà cochées, alors que rien n'y avait jamais été préparé.
--
-- Le geste de comptoir est repositionné là où il doit être : une ligne par
-- (commande, item d'ordonnance). Présence de ligne = préparé — pas de
-- colonne booléenne, décocher = DELETE, cocher = INSERT. `prepared_at` garde
-- une trace horodatée du geste comptoir.

CREATE TABLE pharmacy_order_item_prepared (
    order_id             UUID        NOT NULL REFERENCES pharmacy_order(id),
    prescription_item_id UUID        NOT NULL REFERENCES prescription_item(id),
    prepared_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (order_id, prescription_item_id)
);

REVOKE ALL ON pharmacy_order_item_prepared FROM nubia_app;
GRANT SELECT, INSERT, DELETE ON pharmacy_order_item_prepared TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON pharmacy_order_item_prepared TO nubia_seed;

ALTER TABLE pharmacy_order_item_prepared ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_order_item_prepared FORCE ROW LEVEL SECURITY;

-- Pharmacie : lit/coche/décoche les lignes de SES commandes uniquement.
-- Borne directe sur order_id (pas de bascule vers app.current_cabinet_id
-- comme l'ancien UPDATE prescription_item — la case est désormais une donnée
-- de la commande, pas de l'ordonnance).
CREATE POLICY pharmacy_order_item_prepared_pharmacy ON pharmacy_order_item_prepared
    FOR ALL TO nubia_app
    USING (
        order_id IN (
            SELECT id FROM pharmacy_order
            WHERE pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid
        )
    )
    WITH CHECK (
        order_id IN (
            SELECT id FROM pharmacy_order
            WHERE pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid
        )
    );

-- Patient : lecture seule, bornée à ses commandes (même ancre que
-- pharmacy_order_patient_select, 0124) — nécessaire à GET /v1/account/orders/{id}.
CREATE POLICY pharmacy_order_item_prepared_patient_select ON pharmacy_order_item_prepared
    FOR SELECT TO nubia_app
    USING (
        order_id IN (
            SELECT id FROM pharmacy_order
            WHERE patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        )
    );

CREATE POLICY pharmacy_order_item_prepared_seed_all ON pharmacy_order_item_prepared
    TO nubia_seed USING (true) WITH CHECK (true);

COMMENT ON TABLE pharmacy_order_item_prepared IS
    'Case « sortie des rayons » par (commande, ligne) — #8340, remplace prescription_item.prepared (#6783) qui survivait à tort au cycle de vie de la commande (bleed cross-commande, voire cross-officine, après un refus).';

-- La colonne n'a plus aucun lecteur/écrivain (cf. #8340 : elle restait vraie
-- entre deux commandes successives sur la même ordonnance).
ALTER TABLE prescription_item DROP COLUMN prepared;
