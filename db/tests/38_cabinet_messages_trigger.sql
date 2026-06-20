-- 38_cabinet_messages_trigger.sql — DB-T023 : trigger cabinet_messages_set_updated_at.
-- Vérifie : trigger présent + UPDATE → updated_at changé.
-- pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS). Issue : #2237.

BEGIN;
SELECT * FROM no_plan();

SET LOCAL app.current_cabinet_id = '22370000-0000-0000-0000-000000000001';

INSERT INTO cabinet (id, raison_sociale) VALUES
    ('22370000-0000-0000-0000-000000000001', 'Cabinet T023');

INSERT INTO app_user (id, email, kind) VALUES
    ('22370000-0000-0000-0000-0000000000a1', 'sender@t023.test', 'pro');

-- updated_at antérieur à now() pour mesurer le delta après UPDATE
INSERT INTO cabinet_messages (id, cabinet_id, sender_id, body, updated_at) VALUES
    ('22370000-0000-0000-0000-000000000002',
     '22370000-0000-0000-0000-000000000001',
     '22370000-0000-0000-0000-0000000000a1',
     'message initial',
     now() - interval '1 second');

SELECT ok(
    EXISTS(SELECT 1 FROM pg_trigger
           WHERE tgrelid = 'cabinet_messages'::regclass
             AND tgname   = 'cabinet_messages_set_updated_at'),
    '⭐ trigger cabinet_messages_set_updated_at présent (DB-T023)');

UPDATE cabinet_messages SET body = 'modifié'
    WHERE id = '22370000-0000-0000-0000-000000000002';

SELECT ok(
    (SELECT updated_at FROM cabinet_messages
      WHERE id = '22370000-0000-0000-0000-000000000002')
    > (now() - interval '1 second'),
    '⭐ trigger : updated_at > valeur initiale après UPDATE (DB-T023)');

SELECT * FROM finish();
ROLLBACK;
