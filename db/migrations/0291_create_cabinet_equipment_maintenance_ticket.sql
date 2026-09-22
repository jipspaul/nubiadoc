-- 0291_create_cabinet_equipment_maintenance_ticket.sql
-- [DP-F18.a] Équipements du cabinet + tickets de maintenance (#7168).
--
-- cabinet_equipment : inventaire du matériel du cabinet (fauteuil, autoclave,
-- compresseur…), avec localisation (room), fournisseur et contact technicien
-- (technician_email/technician_phone en texte libre — pas forcément un
-- app_user, souvent un prestataire externe), achat et prochaine échéance de
-- contrôle. Jusqu'ici l'autoclave n'était référencé qu'en texte libre
-- (sterilization_cycle.autoclave_ref, migration 0190) — aucun inventaire
-- structuré du matériel n'existait.
--
-- maintenance_ticket : incident/demande d'intervention sur un équipement
-- (equipment_id nullable : un ticket peut concerner un problème non encore
-- rattaché à une fiche équipement). reported_by référence l'app_user
-- déclarant (interne) ; assigned_to_email est du texte libre (souvent un
-- prestataire externe, même esprit que cabinet_equipment.technician_email).
--
-- maintenance_ticket_photo : photos jointes à un ticket, réutilisant le
-- coffre-fort `document` existant (catégorie 'photo', migration 0004) plutôt
-- que de dupliquer le stockage binaire.
--
-- FK COMPOSITES (equipment_id/ticket_id/document_id + cabinet_id) plutôt que
-- des FK simples : PostgreSQL fait bypasser la RLS aux vérifications
-- d'intégrité référentielle (FK) même sous FORCE ROW LEVEL SECURITY
-- (#4137/migration 0190) — même pattern que compliance_item (0289) /
-- quote_attachment (0278). document_id_cabinet_uniq existe déjà (0210) ;
-- cabinet_equipment_id_cabinet_uniq et maintenance_ticket_id_cabinet_uniq
-- sont créées ci-dessous pour les mêmes besoins.

CREATE TABLE cabinet_equipment (
    id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id         uuid        NOT NULL REFERENCES cabinet(id),
    label              text        NOT NULL,
    category           text        NOT NULL,
    room               text,
    supplier           text,
    technician_email   text,
    technician_phone   text,
    purchased_at       date,
    next_check_at      date,
    created_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cabinet_equipment_label_not_blank CHECK (btrim(label) <> ''),
    CONSTRAINT cabinet_equipment_category_not_blank CHECK (btrim(category) <> ''),
    CONSTRAINT cabinet_equipment_id_cabinet_uniq UNIQUE (id, cabinet_id)
);

CREATE INDEX idx_cabinet_equipment_cabinet_category
    ON cabinet_equipment (cabinet_id, category);
CREATE INDEX idx_cabinet_equipment_cabinet_next_check
    ON cabinet_equipment (cabinet_id, next_check_at)
    WHERE next_check_at IS NOT NULL;

CREATE TABLE maintenance_ticket (
    id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id         uuid        NOT NULL REFERENCES cabinet(id),
    equipment_id       uuid,
    title              text        NOT NULL,
    description        text,
    priority           text        NOT NULL DEFAULT 'medium'
                                    CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
    status             text        NOT NULL DEFAULT 'open'
                                    CHECK (status IN ('open', 'in_progress', 'resolved', 'cancelled')),
    reported_by        uuid        NOT NULL REFERENCES app_user(id),
    assigned_to_email  text,
    created_at         timestamptz NOT NULL DEFAULT now(),
    resolved_at        timestamptz,
    FOREIGN KEY (equipment_id, cabinet_id)
        REFERENCES cabinet_equipment (id, cabinet_id),
    CONSTRAINT maintenance_ticket_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT maintenance_ticket_resolved_consistency
        CHECK (NOT (status = 'resolved' AND resolved_at IS NULL)),
    CONSTRAINT maintenance_ticket_id_cabinet_uniq UNIQUE (id, cabinet_id)
);

CREATE INDEX idx_maintenance_ticket_cabinet_status
    ON maintenance_ticket (cabinet_id, status);
CREATE INDEX idx_maintenance_ticket_equipment
    ON maintenance_ticket (equipment_id)
    WHERE equipment_id IS NOT NULL;

CREATE TABLE maintenance_ticket_photo (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id  uuid        NOT NULL REFERENCES cabinet(id),
    ticket_id   uuid        NOT NULL,
    document_id uuid        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (ticket_id, cabinet_id)
        REFERENCES maintenance_ticket (id, cabinet_id),
    FOREIGN KEY (document_id, cabinet_id)
        REFERENCES document (id, cabinet_id),
    CONSTRAINT maintenance_ticket_photo_ticket_document_uniq UNIQUE (ticket_id, document_id)
);

CREATE INDEX idx_maintenance_ticket_photo_cabinet_ticket
    ON maintenance_ticket_photo (cabinet_id, ticket_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_equipment TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON maintenance_ticket TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON maintenance_ticket_photo TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_equipment TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON maintenance_ticket TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON maintenance_ticket_photo TO nubia_seed;

-- RLS : isolation par cabinet (fail-closed : GUC absent → 0 ligne) sur les
-- trois tables.
ALTER TABLE cabinet_equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE cabinet_equipment FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON cabinet_equipment
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE maintenance_ticket ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_ticket FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON maintenance_ticket
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE maintenance_ticket_photo ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_ticket_photo FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON maintenance_ticket_photo
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE cabinet_equipment IS
    'Inventaire du matériel du cabinet (fauteuil, autoclave, compresseur…) : localisation, fournisseur, contact technicien, achat, prochain contrôle. Table tenant (cabinet_id). RLS fail-closed. #7168.';
COMMENT ON TABLE maintenance_ticket IS
    'Ticket de maintenance sur un équipement (optionnel) : priorité, statut, déclarant, assignation. Table tenant (cabinet_id). RLS fail-closed. #7168.';
COMMENT ON TABLE maintenance_ticket_photo IS
    'Photos jointes à un ticket de maintenance, réutilisant le coffre-fort `document`. Table tenant (cabinet_id). RLS fail-closed. #7168.';
