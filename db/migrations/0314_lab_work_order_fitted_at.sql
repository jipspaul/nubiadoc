-- 0314_lab_work_order_fitted_at.sql
-- Date de transition vers le statut "fitted" (pose, #6878) sur
-- lab_work_order — jusqu'ici seule `sent_at` (date d'envoi au labo) était
-- enregistrée, le front n'avait donc aucune date de pose à afficher
-- (« Posé le … ») ni à filtrer pour bornir le compteur de la colonne
-- "Posé" aux 30 derniers jours (maquette design-v2, point 3).
--
-- Backfill des lignes déjà `fitted` avec `sent_at` : seule date disponible
-- pour ces bons, la vraie date de pose n'a jamais été tracée avant ce
-- correctif (approximation assumée, pas de nouvelle donnée à inventer).

ALTER TABLE lab_work_order
    ADD COLUMN fitted_at timestamptz;

UPDATE lab_work_order
    SET fitted_at = sent_at
    WHERE status = 'fitted' AND fitted_at IS NULL;

COMMENT ON COLUMN lab_work_order.fitted_at IS
    'Date de pose (transition vers le statut fitted), #6878. Backfillée à '
    'sent_at pour les lignes déjà fitted au moment de la migration.';
