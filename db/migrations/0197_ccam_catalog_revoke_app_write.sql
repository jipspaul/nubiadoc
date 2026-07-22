-- 0197_ccam_catalog_revoke_app_write.sql
-- REVOKE INSERT/UPDATE/DELETE sur les catalogues CCAM pour nubia_app (#4281).
--
-- ALTER DEFAULT PRIVILEGES (migration 0001) accorde SELECT/INSERT/UPDATE/
-- DELETE à nubia_app sur TOUTE nouvelle table du schéma public, additivement
-- et indépendamment de tout GRANT plus étroit écrit dans la migration de
-- création de la table. `GRANT SELECT ON foo TO nubia_app;` seul ne retire
-- rien : INSERT/UPDATE/DELETE restent accordés silencieusement via le
-- privilège par défaut — il faut un `REVOKE ALL ... FROM nubia_app;`
-- explicite AVANT le GRANT plus étroit (même pattern que audit_log,
-- migrations 0008/0011, et dental_chart_history, #4121).
--
-- Gap découvert en implémentant #4127 (mutuelle_referentiel) : 3 tables
-- catalogue déjà mergées et documentées « lecture seule pour nubia_app »
-- n'avaient jamais reçu ce REVOKE — nubia_app (donc tout code applicatif
-- runtime, API ou worker) pouvait en réalité INSERT/UPDATE/DELETE sur des
-- référentiels nationaux/plateforme censés être immuables côté app,
-- écriture réservée à nubia_seed.

REVOKE INSERT, UPDATE, DELETE ON ccam_act FROM nubia_app;
REVOKE INSERT, UPDATE, DELETE ON ccam_act_bundle FROM nubia_app;
REVOKE INSERT, UPDATE, DELETE ON ccam_act_bundle_item FROM nubia_app;
REVOKE INSERT, UPDATE, DELETE ON ccam_act_incompatibility FROM nubia_app;
