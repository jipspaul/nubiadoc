-- 0317_cabinet_messages_pinned.sql
-- Épinglage d'un message interne (#5130, bloc « ÉPINGLÉ » de l'aside
-- design-v2) : jusqu'ici ni la colonne ni la route `POST .../:id/pin`
-- n'existaient, rendant le bloc structurellement inalimentable (#8181).

ALTER TABLE cabinet_messages
    ADD COLUMN pinned    boolean     NOT NULL DEFAULT false,
    ADD COLUMN pinned_by uuid        REFERENCES app_user(id),
    ADD COLUMN pinned_at timestamptz;

COMMENT ON COLUMN cabinet_messages.pinned IS
    'Épinglage en tête d''aside (#8181) — posé via POST /v1/cabinet/messages/:id/pin.';
COMMENT ON COLUMN cabinet_messages.pinned_by IS
    'Auteur de l''épinglage (#8181), distinct de sender_id.';
COMMENT ON COLUMN cabinet_messages.pinned_at IS
    'Horodatage de l''épinglage (#8181).';
