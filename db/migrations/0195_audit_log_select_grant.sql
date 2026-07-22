-- 0195_audit_log_select_grant.sql
-- Consultation du journal d'accès (#4155, préalable à GET /v1/cabinet/audit-log,
-- rôle admin) : audit_log n'avait que INSERT pour nubia_app (migration 0008)
-- — écrit mais jamais relu par l'application, empêchant toute réponse aux
-- demandes de contrôle CNIL/patient.
--
-- Ajoute SELECT uniquement : append-only reste garanti (UPDATE/DELETE
-- toujours révoqués, jamais rétablis ici) — lecture seule, aucune régression
-- sur la propriété d'immutabilité de l'audit trail. La policy RLS
-- tenant_isolation (migration 0011) est déjà `FOR ALL`, donc déjà appliquée
-- à SELECT sans changement de policy : seul le GRANT manquait.
--
-- GRANT SELECT sur la table partitionnée mère suffit — PostgreSQL 11+
-- vérifie le privilège SELECT au niveau parent, pas besoin de le répéter sur
-- chaque partition (même raisonnement que le GRANT INSERT de 0008, "routage
-- vers les partitions via le parent").

GRANT SELECT ON audit_log TO nubia_app;
