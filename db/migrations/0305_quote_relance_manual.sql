-- 0305_quote_relance_manual.sql
-- #6970 : le bouton secrétariat « Relancer » sur un devis `sent` appelait
-- POST /v1/cabinet/quotes/:id/send, dont la garde d'idempotence (0207)
-- rend un 200 no-op pour tout devis déjà `sent` — aucune notification.
-- Nouveau endpoint dédié POST /v1/cabinet/quotes/:id/remind (api/src/quote_relances.rs)
-- qui trace la relance manuelle dans `quote_relance` (milestone 'manual').
--
-- Contrairement aux jalons automatiques j3/j7 (un seul par devis, garde
-- ON CONFLICT DO NOTHING de quote_relance_dispatch.rs), une relance
-- manuelle est répétable à volonté par le secrétariat : la contrainte
-- UNIQUE(quote_id, milestone) de 0207 devient un index partiel qui ne
-- porte plus que sur les jalons automatiques.

ALTER TABLE quote_relance DROP CONSTRAINT quote_relance_milestone_check;
ALTER TABLE quote_relance ADD CONSTRAINT quote_relance_milestone_check
    CHECK (milestone IN ('j3', 'j7', 'manual'));

ALTER TABLE quote_relance DROP CONSTRAINT quote_relance_quote_id_milestone_key;
CREATE UNIQUE INDEX quote_relance_auto_milestone_uniq ON quote_relance (quote_id, milestone)
    WHERE milestone IN ('j3', 'j7');
