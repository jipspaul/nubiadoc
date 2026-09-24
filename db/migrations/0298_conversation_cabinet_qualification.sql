-- 0298_conversation_cabinet_qualification.sql
-- [DP-F24.a] Qualification des conversations cabinet (#7152) : origine,
-- motif, priorité, assignation, synthèse.
--
-- origin/motif/priority/assignee_user_id/summary sont nullables : les
-- conversations existantes (tous scopes confondus — patient_cabinet,
-- patient_pharmacy, platform_support, migrations 0007/0126/0169) n'ont pas
-- cette qualification a posteriori, et seul le scope patient_cabinet est
-- concerné par ce triage cabinet.
-- priority reprend l'énumération de maintenance_ticket.priority (migration
-- 0291) pour rester cohérent dans le produit.
--
-- status : colonne existante depuis 0007 avec CHECK ('open','closed'). Le
-- workflow de qualification cabinet demandé ici ('open','in_progress','done')
-- élargit l'énumération au lieu de la remplacer — 'closed' n'est utilisé par
-- aucun code applicatif ni seed à ce jour, mais le retirer casserait
-- silencieusement le contrat des scopes patient_pharmacy/platform_support qui
-- partagent la même colonne. Élargir est donc le choix minimal et non
-- destructif (même esprit que la migration 0169).
--
-- assignee_user_id référence app_user(id) directement (pas de FK composite
-- avec cabinet_id) : app_user n'est pas une table tenant-scopée (rattachement
-- via cabinet_membership, migration 0002) — même pattern que
-- maintenance_ticket.reported_by (migration 0291).

ALTER TABLE conversation
    ADD COLUMN IF NOT EXISTS origin text
        CHECK (origin IN ('phone','app','web','email','other')),
    ADD COLUMN IF NOT EXISTS motif text,
    ADD COLUMN IF NOT EXISTS priority text
        CHECK (priority IN ('low','medium','high','urgent')),
    ADD COLUMN IF NOT EXISTS assignee_user_id uuid REFERENCES app_user(id),
    ADD COLUMN IF NOT EXISTS summary text;

ALTER TABLE conversation
    DROP CONSTRAINT conversation_status_check,
    ADD CONSTRAINT conversation_status_check
        CHECK (status IN ('open','in_progress','done','closed'));

CREATE INDEX IF NOT EXISTS idx_conversation_cabinet_status_priority
    ON conversation (cabinet_id, status, priority);

COMMENT ON COLUMN conversation.origin IS
    'Canal d''origine de la prise de contact (phone|app|web|email|other). Nullable. Issue #7152.';
COMMENT ON COLUMN conversation.motif IS
    'Motif libre de la conversation cabinet. Nullable. Issue #7152.';
COMMENT ON COLUMN conversation.priority IS
    'Priorité de traitement (low|medium|high|urgent), même énumération que maintenance_ticket.priority (0291). Nullable. Issue #7152.';
COMMENT ON COLUMN conversation.assignee_user_id IS
    'app_user assigné au traitement de la conversation cabinet. Nullable. Issue #7152.';
COMMENT ON COLUMN conversation.summary IS
    'Synthèse libre de la conversation, renseignée par le secrétariat/praticien. Nullable. Issue #7152.';
