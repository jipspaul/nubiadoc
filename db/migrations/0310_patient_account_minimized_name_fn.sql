-- 0310_patient_account_minimized_name_fn.sql
-- #6891 (symptôme de #6635 toujours présent) : `patient_display_name`
-- (conversation, scope patient_pharmacy) n'est calculé QU'À LA CRÉATION du
-- fil (api/src/messaging.rs, create_pharmacy_conversation) — jamais
-- rattrapé ensuite. Le catch-up one-shot (0260) ne couvre que les comptes
-- dont le nom était déjà renseigné ; pour les autres la colonne reste NULL
-- pour toujours et le pharmacien voit « Patient » sur 3 fils sur 4,
-- indiscernables (api/src/pharmacy/messaging.rs, COALESCE(..., 'Patient')).
--
-- Plutôt qu'un nouveau rattrapage one-shot (même mode d'échec que #6607 et
-- #6635 : une donnée dénormalisée gelée se re-désynchronise), on calcule le
-- nom minimisé À LA LECTURE à partir de `patient_account`, comme le fait
-- déjà `minimized_patient_name()` (api/src/pharmacy/orders.rs) pour chaque
-- commande. `patient_account` est en RLS plateforme (`app.current_account_id`
-- = soi-même) : une session pharmacie ne peut pas la lire par jointure
-- directe. Même remède que `practitioner_person_name` (0304) et
-- `practitioner_display_name` (0258) : fonction SECURITY DEFINER dédiée,
-- contourne la RLS pour cette seule lecture (nom minimisé, pas une donnée
-- sensible côté pharmacie — déjà exposé via patient_display_name/pharmacy_order).

CREATE FUNCTION patient_account_minimized_name(p_patient_account_id uuid)
    RETURNS text
    LANGUAGE sql
    SECURITY DEFINER
    STABLE
    SET search_path = public
AS $$
    SELECT NULLIF(
        pa.first_name || CASE
            WHEN length(pa.last_name) > 0 THEN ' ' || upper(left(pa.last_name, 1)) || '.'
            ELSE ''
        END,
        ''
    )
    FROM patient_account pa
    WHERE pa.id = p_patient_account_id;
$$;

GRANT EXECUTE ON FUNCTION patient_account_minimized_name(uuid) TO nubia_app;
