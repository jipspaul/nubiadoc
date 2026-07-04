-- 0124_pharmacy_order.sql
-- Commande click-and-collect ET objet de partage d'ordonnance cross-tenant.
-- Trois ancres RLS permissives : la pharmacie (GUC app.current_pharmacy_id),
-- le patient (GUC app.patient_account_id) et le cabinet d'origine (GUC
-- app.current_cabinet_id) ne voient chacun que leurs lignes.
-- La pharmacie ne lit JAMAIS les tables cliniques : elle n'accède qu'au PDF
-- signé via la policy document_pharmacy_read (pattern 0034), bornée à ses
-- commandes. Cf. docs/07-conformite.md §4 (cloisonnement) — révision AIPD à
-- déclencher (§3.5).
-- Machine à états : received → preparing → ready → picked_up,
-- + rejected (pharmacien, motif requis) et cancelled (patient).
-- patient_display_name : minimisé (« Prénom N. »), nécessaire au comptoir ;
-- pas de chiffrement colonne tant que core/crypto est un scaffold (NUB-T3) —
-- même niveau d'exposition que quote.patient_name existant.
-- Issue : #3307 (épic #3323)

CREATE TABLE pharmacy_order (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    pharmacy_id             UUID        NOT NULL REFERENCES pharmacy(id),
    cabinet_id              UUID        NOT NULL REFERENCES cabinet(id),
    patient_account_id      UUID        NOT NULL REFERENCES patient_account(id),
    prescription_id         UUID        NOT NULL REFERENCES prescription(id),
    document_id             UUID        NOT NULL REFERENCES document(id),
    created_by_kind         TEXT        NOT NULL CHECK (created_by_kind IN ('patient', 'practitioner')),
    created_by              UUID,
    consent_record_id       UUID        REFERENCES consent_record(id),
    status                  TEXT        NOT NULL DEFAULT 'received'
        CHECK (status IN ('received', 'preparing', 'ready', 'picked_up', 'rejected', 'cancelled')),
    pharmacy_name           TEXT        NOT NULL,
    patient_display_name    TEXT        NOT NULL,
    pickup_token_hash       CHAR(64),
    pickup_token_expires_at TIMESTAMPTZ,
    picked_up_by            UUID,
    rejection_reason        TEXT,
    received_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    preparing_at            TIMESTAMPTZ,
    ready_at                TIMESTAMPTZ,
    picked_up_at            TIMESTAMPTZ,
    cancelled_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Une seule commande active par ordonnance (le retrait/refus/annulation libère).
CREATE UNIQUE INDEX pharmacy_order_active_prescription
    ON pharmacy_order (prescription_id)
    WHERE status IN ('received', 'preparing', 'ready');

-- File de la pharmacie (filtre par statut) et suivi patient.
CREATE INDEX idx_pharmacy_order_pharmacy_status ON pharmacy_order (pharmacy_id, status);
CREATE INDEX idx_pharmacy_order_account ON pharmacy_order (patient_account_id);

-- Résolution du scan par hash de token (single-use, lot B3).
CREATE UNIQUE INDEX pharmacy_order_pickup_token_hash
    ON pharmacy_order (pickup_token_hash)
    WHERE pickup_token_hash IS NOT NULL;

-- Append-only sauf transitions : pas de DELETE pour l'app (REVOKE explicite,
-- les droits par défaut de 0001 donneraient DELETE — pattern 0053).
REVOKE ALL ON pharmacy_order FROM nubia_app;
GRANT SELECT, INSERT, UPDATE ON pharmacy_order TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON pharmacy_order TO nubia_seed;

ALTER TABLE pharmacy_order ENABLE ROW LEVEL SECURITY;
ALTER TABLE pharmacy_order FORCE ROW LEVEL SECURITY;

-- Pharmacie : lecture + transitions de préparation/retrait sur ses commandes.
-- WITH CHECK interdit de forger une annulation (réservée au patient).
CREATE POLICY pharmacy_order_pharmacy_select ON pharmacy_order
    FOR SELECT TO nubia_app
    USING (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid);
CREATE POLICY pharmacy_order_pharmacy_update ON pharmacy_order
    FOR UPDATE TO nubia_app
    USING (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid)
    WITH CHECK (
        pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid
        AND status <> 'cancelled'
    );

-- Patient : voit et crée ses commandes ; UPDATE limité (annulation, token de
-- retrait) — WITH CHECK interdit de forger picked_up/rejected (réservés au
-- scan pharmacie et au pharmacien).
CREATE POLICY pharmacy_order_patient_select ON pharmacy_order
    FOR SELECT TO nubia_app
    USING (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid);
CREATE POLICY pharmacy_order_patient_insert ON pharmacy_order
    FOR INSERT TO nubia_app
    WITH CHECK (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid);
CREATE POLICY pharmacy_order_patient_update ON pharmacy_order
    FOR UPDATE TO nubia_app
    USING (patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid)
    WITH CHECK (
        patient_account_id = nullif(current_setting('app.patient_account_id', true), '')::uuid
        AND status NOT IN ('picked_up', 'rejected')
    );

-- Cabinet d'origine : voit les commandes issues de ses ordonnances et en crée
-- (envoi par le praticien). Pas d'UPDATE : le cabinet n'agit pas sur la file.
CREATE POLICY pharmacy_order_cabinet_select ON pharmacy_order
    FOR SELECT TO nubia_app
    USING (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);
CREATE POLICY pharmacy_order_cabinet_insert ON pharmacy_order
    FOR INSERT TO nubia_app
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY pharmacy_order_seed_all ON pharmacy_order
    TO nubia_seed USING (true) WITH CHECK (true);

-- La pharmacie accède au PDF signé de SES commandes uniquement (pattern 0034).
-- Le sous-select est lui-même filtré par la policy pharmacy_order_pharmacy_select.
CREATE POLICY document_pharmacy_read ON document
    FOR SELECT TO nubia_app
    USING (
        id IN (
            SELECT document_id FROM pharmacy_order
            WHERE pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid
        )
    );

COMMENT ON TABLE pharmacy_order IS
    'Commande click-and-collect + partage d''ordonnance cross-tenant (3 ancres RLS : pharmacie/patient/cabinet). Une commande active max par ordonnance. Réf. épic #3323, docs/07 §4.';

-- ---------------------------------------------------------------------------
-- Pharmacie déclarée du patient (GET/PUT /v1/account/pharmacy).
-- ---------------------------------------------------------------------------
ALTER TABLE patient_account
    ADD COLUMN pharmacy_id UUID REFERENCES pharmacy(id);

-- Le praticien présélectionne la pharmacie déclarée du patient à l'envoi
-- d'une ordonnance (GET /v1/cabinet/patients/{id}/pharmacy). patient_account
-- est account-scoped (0045) : cette fonction SECURITY DEFINER fait le pont,
-- bornée à la pharmacie déclarée (aucune autre donnée du compte). Le handler
-- DOIT d'abord vérifier via RLS que le patient appartient au cabinet courant
-- (anti-probing cross-cabinet).
CREATE FUNCTION patient_declared_pharmacy(p_patient_id uuid)
    RETURNS TABLE(pharmacy_id uuid, raison_sociale text, address jsonb, phone text)
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT ph.id, ph.raison_sociale, ph.address, ph.phone
    FROM patient p
    JOIN patient_account pa ON pa.id = p.patient_account_id
    JOIN pharmacy ph ON ph.id = pa.pharmacy_id AND ph.deleted_at IS NULL
    WHERE p.id = p_patient_id;
$$;

GRANT EXECUTE ON FUNCTION patient_declared_pharmacy(uuid) TO nubia_app;
