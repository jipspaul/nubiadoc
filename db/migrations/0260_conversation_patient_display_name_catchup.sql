-- 0260_conversation_patient_display_name_catchup.sql
-- #6635 : patient_display_name (conversation, scope patient_pharmacy) n'est
-- calculé qu'à la CRÉATION du fil (api/src/messaging.rs,
-- create_pharmacy_conversation) et jamais rattrapé ensuite. Les fils créés
-- avant que ce champ existe, ou dont first_name/last_name étaient vides à cet
-- instant (NULL via `then_some`), restent NULL pour toujours : côté pharmacie
-- ils s'affichent tous comme « Patient », indiscernables les uns des autres
-- (api/src/pharmacy/messaging.rs, COALESCE(..., 'Patient')). Pharmacy n'a pas
-- accès à patient_account en RLS (app.current_account_id) : la migration,
-- exécutée par nubia_owner, la contourne pour ce rattrapage one-shot. Même
-- mode d'échec que #6607.

UPDATE conversation c
SET patient_display_name = pa.first_name || CASE
    WHEN length(pa.last_name) > 0 THEN ' ' || upper(left(pa.last_name, 1)) || '.'
    ELSE ''
END
FROM patient_account pa
WHERE c.patient_account_id = pa.id
  AND c.pharmacy_id IS NOT NULL
  AND c.patient_display_name IS NULL
  AND pa.first_name || CASE
        WHEN length(pa.last_name) > 0 THEN ' ' || upper(left(pa.last_name, 1)) || '.'
        ELSE ''
      END <> '';
