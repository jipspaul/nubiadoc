-- 0097_conversation_subject.sql
-- Ajoute la colonne subject (nullable) à conversation.
-- Permet POST /v1/conversations body { cabinet_id, subject? } (issue #1669).
-- subject est libre (patient peut poser un objet court, ex. "Question prothèse").
-- Nullable : une conversation peut être créée sans objet explicite.

ALTER TABLE conversation
    ADD COLUMN IF NOT EXISTS subject text;
