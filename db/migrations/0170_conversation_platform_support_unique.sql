-- 0170_conversation_platform_support_unique.sql
-- Une seule conversation de support par cabinet (#4169) : POST
-- /v1/support/conversations doit être idempotent (ré-ouvrir le même canal
-- de support à chaque appel, pas créer un nouveau fil à chaque clic).
-- Même pattern que conversation_uniq_patient_account_cabinet (migration 0036),
-- en partiel (scope = 'platform_support') pour ne contraindre que ce scope.

CREATE UNIQUE INDEX conversation_uniq_platform_support_cabinet
    ON conversation (cabinet_id)
    WHERE scope = 'platform_support';

COMMENT ON INDEX conversation_uniq_platform_support_cabinet IS
    'Un seul fil de support plateforme par cabinet — POST /v1/support/conversations '
    'est idempotent (ON CONFLICT ... RETURNING). Issue #4169.';
