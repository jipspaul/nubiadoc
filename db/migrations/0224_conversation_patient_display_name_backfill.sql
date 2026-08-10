-- 0224_conversation_patient_display_name_backfill.sql
-- patient_display_name était calculé une seule fois à la création du fil
-- (api/src/messaging.rs, create_pharmacy_conversation) : si first_name/last_name
-- du compte patient étaient des chaînes vides (pas NULL), la valeur persistée
-- était '' plutôt que NULL. COALESCE(c.patient_display_name, 'Patient')
-- (api/src/pharmacy/messaging.rs) ne remplace que NULL, jamais '' : le
-- fallback documenté n'était donc jamais atteint pour ces fils.
-- Backfill : bascule les chaînes vides existantes en NULL pour que le
-- fallback 'Patient' s'applique en lecture. Issue : #4663

UPDATE conversation
SET patient_display_name = NULL
WHERE patient_display_name = '';
