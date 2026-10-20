-- 0318_cabinet_messages_reference.sql
-- Référence à un objet du produit (#5131, encadré 3 « Citer un objet du
-- produit » de la maquette) attachée à un message interne : jusqu'ici ni
-- colonne, ni champ de réponse, ni paramètre d'envoi n'existaient, rendant
-- le bloc « Éléments cités aujourd'hui » de l'aside structurellement
-- inalimentable — seconde moitié de #8181, restée non traitée après #8195
-- (qui n'a livré que l'épinglage). Issue : #8208.

ALTER TABLE cabinet_messages
    ADD COLUMN reference_type       text,
    ADD COLUMN reference_target_id  uuid,
    ADD COLUMN reference_title      text,
    ADD COLUMN reference_subtitle   text,
    ADD CONSTRAINT cabinet_messages_reference_type_check
        CHECK (reference_type IS NULL OR reference_type IN (
            'patient', 'devis', 'lab_work_order', 'stock_request', 'agenda_slot'
        )),
    ADD CONSTRAINT cabinet_messages_reference_all_or_none_check
        CHECK (
            (reference_type IS NULL AND reference_target_id IS NULL
                AND reference_title IS NULL AND reference_subtitle IS NULL)
            OR
            (reference_type IS NOT NULL AND reference_target_id IS NOT NULL
                AND reference_title IS NOT NULL AND reference_subtitle IS NOT NULL)
        );

COMMENT ON COLUMN cabinet_messages.reference_type IS
    'Type d''objet produit cité (#8208) : patient/devis/lab_work_order/stock_request/agenda_slot.';
COMMENT ON COLUMN cabinet_messages.reference_target_id IS
    'Id de l''objet référencé (#8208) — pas de FK : la table cible dépend de reference_type.';
COMMENT ON COLUMN cabinet_messages.reference_title IS
    'Titre affiché par la carte de référence en ligne (#8208).';
COMMENT ON COLUMN cabinet_messages.reference_subtitle IS
    'Sous-titre affiché par la carte de référence en ligne (#8208).';
