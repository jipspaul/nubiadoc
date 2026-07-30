-- 0206_quote_sent_at.sql
-- quote.sent_at (#4126) : aucune colonne ne date le passage à status='sent'
-- (created_at/updated_at existent mais updated_at est touché par d'autres
-- opérations, pas fiable pour calculer "depuis combien de temps ce devis
-- est en attente de signature"). Nécessaire pour les relances J+3/J+7.
--
-- Backfill best-effort sur les devis déjà 'sent' à cette migration :
-- updated_at est la meilleure approximation disponible rétroactivement (la
-- date exacte du dernier passage en 'sent' n'est pas reconstituible sans
-- rejouer audit_log) — n'affecte que le calendrier de relance des devis
-- déjà en attente, pas la donnée métier elle-même.

ALTER TABLE quote
    ADD COLUMN sent_at timestamptz;

UPDATE quote SET sent_at = updated_at WHERE status = 'sent' AND sent_at IS NULL;

COMMENT ON COLUMN quote.sent_at IS
    'Horodatage du passage à status=''sent'' — base du calendrier de relance J+3/J+7 (#4126). NULL si jamais envoyé.';
