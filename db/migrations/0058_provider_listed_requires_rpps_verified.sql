-- 0058_provider_listed_requires_rpps_verified.sql
-- Règle métier : un provider ne peut être listé dans l'annuaire public que s'il est
-- rpps_verified. Enforcer par contrainte DB (commentaire dans 0009 insuffisant).
-- Réf. : issue #791 (Règles métier §2) ; docs/05 §9.3 ; docs/07 §4.7.

ALTER TABLE provider
    ADD CONSTRAINT provider_listed_requires_rpps_verified
    CHECK (is_listed = false OR rpps_verified = true);
