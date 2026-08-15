-- 0230_stock_request_fulfilled_at.sql
-- stock_request.fulfilled_at (jips/nubiadoc#5492) : aucune colonne ne date
-- le passage à status='fulfilled'. Le seul horodatage exposé (created_at)
-- est structurellement le mauvais axe pour un compteur "honorées ce mois"
-- (jips/nubiadoc#5493) — une demande créée en juillet mais honorée en août
-- doit compter en août.
--
-- Backfill exact (pas une approximation) pour les demandes déjà
-- 'fulfilled' : le cycle sent → accepted|rejected → fulfilled est terminal
-- une fois 'fulfilled' atteint (aucune transition ultérieure ne touche la
-- ligne, cf. stock_response), donc updated_at porte déjà l'horodatage exact
-- du dernier changement de statut à cette date.

ALTER TABLE stock_request
    ADD COLUMN fulfilled_at timestamptz;

UPDATE stock_request SET fulfilled_at = updated_at WHERE status = 'fulfilled' AND fulfilled_at IS NULL;

COMMENT ON COLUMN stock_request.fulfilled_at IS
    'Horodatage du passage à status=''fulfilled'' — base du filtre mensuel du compteur "honorées ce mois" (#5493). NULL tant que non honorée.';
