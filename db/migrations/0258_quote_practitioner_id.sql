-- 0258_quote_practitioner_id.sql
-- #6563 : le patient ne peut distinguer ses devis (titres « Devis du
-- 05/09/2026 » identiques) et l'écran de signature ne montre aucun émetteur.
-- `quote` n'a jamais porté de praticien (contrairement à `appointment`,
-- `prescription`, `treatment_plan`) : impossible d'exposer
-- `practitioner_name` côté patient sans cette colonne. Nullable : les devis
-- existants n'ont pas de valeur rétroactive fiable (pas de backfill).
--
-- FK composite (practitioner_id, cabinet_id) dès la création — pas de FK
-- simple à corriger après coup : Postgres ignore la RLS pour les contraintes
-- FK (cf. audit #4291, migration 0214 `practitioner_children_composite_fk`),
-- un FK simple sur `practitioner(id)` permettrait de référencer un
-- practitioner d'un AUTRE cabinet.

ALTER TABLE quote
    ADD COLUMN practitioner_id uuid,
    ADD CONSTRAINT quote_practitioner_id_cabinet_fkey
        FOREIGN KEY (practitioner_id, cabinet_id) REFERENCES practitioner (id, cabinet_id);

-- `provider` (annuaire) n'est lisible en RLS que si `is_listed = true`
-- (policy `provider_public_read`, migration 0011) ou depuis la session du
-- cabinet propriétaire (`provider_cabinet_manage`, dépend de
-- `app.current_cabinet_id`). Aucun des deux ne matche la session patient
-- (`app.patient_account_id` seul, GET /v1/quotes liste des devis de
-- PLUSIEURS cabinets) : un JOIN direct sur `provider` renverrait `NULL`
-- pour tout praticien non listé publiquement. Même pattern que
-- `user_practitioner_ids` (migration 0254) : fonction SECURITY DEFINER
-- dédiée, contourne la RLS pour cette seule lecture (display_name n'est pas
-- une donnée sensible — nom d'exercice destiné à l'affichage patient).
CREATE FUNCTION practitioner_display_name(p_practitioner_id uuid)
    RETURNS text
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT display_name FROM provider WHERE practitioner_id = p_practitioner_id LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION practitioner_display_name(uuid) TO nubia_app;
