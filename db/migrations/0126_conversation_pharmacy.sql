-- 0126_conversation_pharmacy.sql
-- Généralise la messagerie (conversation/message) aux pharmacies (lot B6,
-- épic #3323) : scope 'patient_pharmacy', ancre RLS pharmacy_id (GUC
-- app.current_pharmacy_id), sender_kind 'pharmacist'.
-- Le cloisonnement triadique est préservé : la policy cabinet
-- (tenant_isolation) filtre sur cabinet_id (NULL pour une conversation
-- pharmacie → invisible aux cabinets) et la policy pharmacie filtre sur
-- pharmacy_id (NULL pour une conversation cabinet → invisible aux pharmacies).
-- patient_display_name : nom minimisé (« Prénom N. ») affiché côté pharmacie,
-- qui ne peut pas lire patient_account (RLS account-scoped).
-- Issue : #3311

ALTER TABLE conversation
    ADD COLUMN pharmacy_id UUID REFERENCES pharmacy(id),
    ADD COLUMN patient_display_name TEXT,
    ALTER COLUMN cabinet_id DROP NOT NULL;

ALTER TABLE conversation
    ADD CONSTRAINT conversation_pharmacy_scope_chk
        CHECK ((pharmacy_id IS NOT NULL) = (scope = 'patient_pharmacy')),
    ADD CONSTRAINT conversation_anchor_chk
        CHECK (cabinet_id IS NOT NULL OR pharmacy_id IS NOT NULL);

-- Une seule conversation par (compte patient, pharmacie).
CREATE UNIQUE INDEX conversation_uniq_account_pharmacy
    ON conversation (patient_account_id, pharmacy_id)
    WHERE pharmacy_id IS NOT NULL;

ALTER TABLE message
    ADD COLUMN pharmacy_id UUID REFERENCES pharmacy(id),
    ALTER COLUMN cabinet_id DROP NOT NULL;

ALTER TABLE message
    ADD CONSTRAINT message_anchor_chk
        CHECK (cabinet_id IS NOT NULL OR pharmacy_id IS NOT NULL);

-- sender_kind : ajoute 'pharmacist'.
ALTER TABLE message DROP CONSTRAINT message_sender_kind_check;
ALTER TABLE message
    ADD CONSTRAINT message_sender_kind_check
        CHECK (sender_kind = ANY (ARRAY['patient'::text, 'secretary'::text,
                                        'practitioner'::text, 'pharmacist'::text]));

-- Ancre RLS pharmacie (fail-closed : GUC absent → aucune ligne).
CREATE POLICY conversation_pharmacy_all ON conversation
    FOR ALL TO nubia_app
    USING (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid)
    WITH CHECK (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid);

CREATE POLICY message_pharmacy_all ON message
    FOR ALL TO nubia_app
    USING (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid)
    WITH CHECK (pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid);

COMMENT ON COLUMN conversation.pharmacy_id IS
    'Ancre du scope patient_pharmacy (lot B6). Exclusif du fil cabinet : cabinet_id NULL. Réf. épic #3323.';
COMMENT ON COLUMN conversation.patient_display_name IS
    'Nom minimisé (« Prénom N. ») pour l''affichage côté pharmacie (qui ne lit pas patient_account).';
