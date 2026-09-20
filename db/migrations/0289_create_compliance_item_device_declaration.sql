-- 0289_create_compliance_item_device_declaration.sql
-- [DP-F17.a] Conformité ARS/DMSM (#7171).
--
-- compliance_item : échéancier de conformité du cabinet — formation
-- obligatoire par membre (subject_user_id), contrôle périodique d'équipement
-- (equipment_label), registre, ou autre. due_date porte l'échéance ;
-- recurrence_months (nullable) porte la périodicité pour les items
-- récurrents (ex. contrôle annuel d'autoclave). status/done_at tracent la
-- réalisation ; evidence_document_id rattache optionnellement le justificatif
-- (attestation de formation, rapport de contrôle) déjà stocké au
-- coffre-fort (`document`).
--
-- custom_device_declaration : déclaration de dispositif médical sur mesure
-- (DMSM) par patient — obligation réglementaire pour les prothèses/appareils
-- fabriqués par un laboratoire sur prescription individuelle.
-- consultation_act_id (nullable) rattache optionnellement l'acte ayant donné
-- lieu à la pose ; document_id (nullable) rattache optionnellement la
-- déclaration numérisée.
--
-- subject_user_id référence app_user(id) en FK simple : app_user est une
-- entité plateforme sans cabinet_id ni RLS (0002) — pas de dimension tenant à
-- composer, même pattern que clinical_note.author_id (0003).
--
-- FK COMPOSITES (patient_id/consultation_act_id/document_id/
-- evidence_document_id + cabinet_id) plutôt que des FK simples : PostgreSQL
-- fait bypasser la RLS aux vérifications d'intégrité référentielle (FK) même
-- sous FORCE ROW LEVEL SECURITY (#4137/migration 0190) — même pattern que
-- quote_attachment (0278). Les UNIQUE (id, cabinet_id) requis existent déjà :
-- patient_id_cabinet_uniq (0193), consultation_act_id_cabinet_uniq (0190),
-- document_id_cabinet_uniq (0210).

CREATE TABLE compliance_item (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id          uuid        NOT NULL REFERENCES cabinet(id),
    kind                text        NOT NULL CHECK (kind IN ('training', 'equipment_check', 'register', 'other')),
    label               text        NOT NULL,
    subject_user_id     uuid        REFERENCES app_user(id),
    equipment_label     text,
    due_date            date        NOT NULL,
    recurrence_months   integer     CHECK (recurrence_months IS NULL OR recurrence_months > 0),
    status              text        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'done', 'overdue')),
    done_at             timestamptz,
    evidence_document_id uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (evidence_document_id, cabinet_id)
        REFERENCES document (id, cabinet_id),
    CONSTRAINT compliance_item_label_not_blank CHECK (btrim(label) <> ''),
    CONSTRAINT compliance_item_done_consistency CHECK ((status = 'done') = (done_at IS NOT NULL))
);

CREATE INDEX idx_compliance_item_cabinet_due
    ON compliance_item (cabinet_id, due_date);
CREATE INDEX idx_compliance_item_subject
    ON compliance_item (subject_user_id)
    WHERE subject_user_id IS NOT NULL;

CREATE TABLE custom_device_declaration (
    id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id          uuid        NOT NULL REFERENCES cabinet(id),
    patient_id          uuid        NOT NULL,
    consultation_act_id uuid,
    lab_name            text        NOT NULL,
    device_description  text        NOT NULL,
    declared_at         timestamptz NOT NULL DEFAULT now(),
    document_id         uuid,
    created_at          timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (patient_id, cabinet_id)
        REFERENCES patient (id, cabinet_id),
    FOREIGN KEY (consultation_act_id, cabinet_id)
        REFERENCES consultation_act (id, cabinet_id),
    FOREIGN KEY (document_id, cabinet_id)
        REFERENCES document (id, cabinet_id),
    CONSTRAINT custom_device_declaration_lab_name_not_blank CHECK (btrim(lab_name) <> ''),
    CONSTRAINT custom_device_declaration_device_description_not_blank CHECK (btrim(device_description) <> '')
);

CREATE INDEX idx_custom_device_declaration_cabinet_patient
    ON custom_device_declaration (cabinet_id, patient_id);
CREATE INDEX idx_custom_device_declaration_consultation_act
    ON custom_device_declaration (consultation_act_id)
    WHERE consultation_act_id IS NOT NULL;

-- RLS tenant (fail-closed : GUC absent → 0 ligne) sur les deux tables.
ALTER TABLE compliance_item ENABLE ROW LEVEL SECURITY;
ALTER TABLE compliance_item FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON compliance_item
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

ALTER TABLE custom_device_declaration ENABLE ROW LEVEL SECURITY;
ALTER TABLE custom_device_declaration FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON custom_device_declaration
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON compliance_item TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON custom_device_declaration TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON compliance_item TO nubia_seed;
GRANT SELECT, INSERT, UPDATE, DELETE ON custom_device_declaration TO nubia_seed;

COMMENT ON TABLE compliance_item IS
    'Échéancier de conformité du cabinet (formation, contrôle d''équipement, registre, autre) : échéance, récurrence, statut, justificatif optionnel. Table tenant (cabinet_id). RLS fail-closed. #7171.';
COMMENT ON TABLE custom_device_declaration IS
    'Déclaration de dispositif médical sur mesure (DMSM) par patient : laboratoire, description, acte/document optionnels. Table tenant (cabinet_id). RLS fail-closed. #7171.';
