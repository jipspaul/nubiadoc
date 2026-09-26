-- 0304_practitioner_person_name_fn.sql
-- #7740 : la carte de liste `GET /v1/treatment-plans` (design-v2, écran ①)
-- doit afficher « Dr <praticien> · proposé le <date> » — le front préfixe
-- déjà lui-même « Dr » (`plan_card.dart`), il attend donc un nom SANS
-- titre. `practitioner_display_name()` (migration 0258) renvoie
-- `provider.display_name`, qui porte déjà « Dr … » en convention (seed) :
-- le réutiliser produirait « Dr Dr Amélie Rousseau ».
--
-- Le nom de la personne vit sur `app_user` (first_name/last_name, migration
-- 0021), pas sur `provider`. Mais `app_user` est en RLS `user_self_select`
-- (migration 0045, `app.current_user_id` = soi-même) : une session patient
-- (`app.patient_account_id` seul) ne peut jamais lire l'`app_user` du
-- praticien par une jointure directe. Même remède que `practitioner_display_name`
-- (0258) et `user_practitioner_ids` (0254) : fonction SECURITY DEFINER dédiée,
-- contourne la RLS pour cette seule lecture (nom d'exercice, pas une donnée
-- sensible côté patient — déjà exposé « Dr <nom> » via les devis/RDV).

CREATE FUNCTION practitioner_person_name(p_practitioner_id uuid)
    RETURNS text
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT NULLIF(trim(concat_ws(' ', u.first_name, u.last_name)), '')
    FROM practitioner p
    JOIN app_user u ON u.id = p.user_id
    WHERE p.id = p_practitioner_id;
$$;

GRANT EXECUTE ON FUNCTION practitioner_person_name(uuid) TO nubia_app;
