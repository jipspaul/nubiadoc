-- 0323_implant_passport_office_fn.sql
-- #6774 : la fiche patient du passeport implantaire doit nommer le cabinet
-- où l'implant a été posé (maquette design-v2, ligne « Cabinet ») — champ
-- déjà lu par le front (`ImplantItemDto.office`, `implant_detail_page.dart`)
-- mais jamais servi par l'API.
--
-- `cabinet` est en RLS `tenant_isolation` (migration 0011, `id =
-- app.current_cabinet_id`) : une session patient (`app.patient_account_id`
-- seul) ne peut jamais lire le nom du cabinet par une jointure directe.
-- Même remède que `practitioner_person_name` (migration 0304) : fonction
-- SECURITY DEFINER dédiée, contourne la RLS pour cette seule lecture (nom
-- commercial du cabinet, pas une donnée sensible côté patient — déjà
-- exposé via les devis/RDV/factures).

CREATE FUNCTION cabinet_display_name(p_cabinet_id uuid)
    RETURNS text
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT raison_sociale FROM cabinet WHERE id = p_cabinet_id;
$$;

GRANT EXECUTE ON FUNCTION cabinet_display_name(uuid) TO nubia_app;
