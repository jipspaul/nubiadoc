-- 0231_quote_expires_at.sql
-- quote.expires_at (#5597) : aucune colonne n'exposait d'échéance de devis
-- côté API/DB (`expires_at`/`valid_until` absent de la table `quote`), alors
-- que le dashboard secrétariat (#5377/#5594) et le badge rail filtrent déjà
-- sur `expiresAt` côté front → carte/badge structurellement vides pour les
-- 40 devis `sent` observés en prod (expiresAt toujours null).
--
-- Durée de validité retenue : 30 jours à compter de l'envoi (`sent_at`),
-- pratique courante pour un devis dentaire/médical en l'absence de valeur
-- métier configurée ailleurs dans le schéma.
--
-- Backfill best-effort sur les devis déjà 'sent' : même base que le backfill
-- de sent_at (migration 0206), n'affecte que l'échéance affichée, pas la
-- donnée métier elle-même.

ALTER TABLE quote
    ADD COLUMN expires_at timestamptz;

UPDATE quote SET expires_at = sent_at + interval '30 days'
    WHERE status = 'sent' AND sent_at IS NOT NULL AND expires_at IS NULL;

COMMENT ON COLUMN quote.expires_at IS
    'Échéance du devis = sent_at + 30 jours, posée au passage à status=''sent'' (#5597). NULL si jamais envoyé.';
