-- 0240_visit_request_estimated_price.sql
-- jips/nubiadoc#6117 : aucune notion de prix n'existe dans le domaine nurse
-- (soins à domicile) — ni endpoint d'estimation, ni colonne. Le patient ne
-- voit jamais aucun montant avant/pendant/après une visite. Ajoute la colonne
-- qui reçoit le prix calculé côté API (`nurse::pricing::estimate_price_cents`)
-- et figé sur la demande dès sa création (`nurse::requests::create_visit_request`).
--
-- DEFAULT 0 : les demandes créées avant ce correctif n'ont jamais eu de prix
-- estimé (feature absente) — 0 documente honnêtement cet état plutôt que de
-- rejouer après coup un barème qui n'existait pas au moment de la demande.
--
-- IF NOT EXISTS (#6136) : ce fichier portait le numéro 0239 avant son
-- renumérotage en 0240 (#6128/dedc207d, résolution de la collision avec
-- `0239_create_account_access_request.sql`). Sur le LXC de prod, cette
-- colonne avait déjà été ajoutée SOUS L'ANCIEN NUMÉRO (239, enregistré dans
-- `_sqlx_migrations` avant le renumérotage) ; `infra/deploy/migrate.sh` ne
-- suit les migrations appliquées QUE par numéro de version, donc le nouveau
-- numéro 240 se voyait rejouer un `ADD COLUMN` sur une colonne déjà présente
-- -> `ALTER TABLE` en erreur -> pipeline `deploy.yml` bloqué en échec sur
-- CHAQUE déploiement depuis ce renumérotage (rien après cette migration ne
-- s'appliquait plus, y compris le redémarrage du conteneur API). IF NOT
-- EXISTS rend le rejeu inoffensif (no-op sur le LXC, ADD normal ailleurs).
ALTER TABLE visit_request
    ADD COLUMN IF NOT EXISTS estimated_price_cents integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN visit_request.estimated_price_cents IS
    'Prix estimé (centimes) affiché au patient avant/à la demande (#6117), calculé par nurse::pricing::estimate_price_cents et figé à la création. 0 = demande créée avant l''ajout de la fonctionnalité.';
