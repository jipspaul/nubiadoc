-- 0205_payment_schedule_provider_ref.sql
-- payment_schedule.provider_ref (#4163) : référence externe du provider
-- (ex. subscription id Alma), même pendant que `payment.provider_ref`
-- (migration 0006) pour la table sœur — manquait sur payment_schedule.
-- NULL tant qu'aucune souscription provider n'a été effectuée (mécanisme
-- provider optionnel sur cette table, cf. commentaire colonne provider).

ALTER TABLE payment_schedule
    ADD COLUMN provider_ref text;

COMMENT ON COLUMN payment_schedule.provider_ref IS
    'Référence externe renvoyée par le provider à la souscription (ex. subscription id Alma). NULL si provider non renseigné ou souscription non applicable. #4163.';
