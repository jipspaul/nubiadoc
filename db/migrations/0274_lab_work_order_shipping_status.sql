-- 0274_lab_work_order_shipping_status.sql
-- Suivi d'expédition/réception du bon de travail prothétique (#7209,
-- DP-F3.a), pour alerter la veille si la prothèse n'est pas revenue du
-- laboratoire avant le rendez-vous de pose.
--
-- CHECK étendu SANS retirer les valeurs existantes ('try_in', 'returned') :
-- migrations forward-only (db/AGENTS.md règle 4), aucune réécriture des
-- lignes déjà en base. Les nouveaux statuts ('in_progress', 'shipped',
-- 'received') s'ajoutent à l'énum existante ; l'API (#4148) migre séparément
-- vers le cycle enrichi.

ALTER TABLE lab_work_order
    ADD COLUMN shipped_at  timestamptz,
    ADD COLUMN received_at timestamptz,
    ADD COLUMN tracking_ref text;

ALTER TABLE lab_work_order
    DROP CONSTRAINT lab_work_order_status_check;
ALTER TABLE lab_work_order
    ADD CONSTRAINT lab_work_order_status_check
    CHECK (status IN ('sent', 'try_in', 'returned', 'fitted',
                       'in_progress', 'shipped', 'received'));

-- Vue du jour : bons de travail attendus par cabinet, triés par échéance.
CREATE INDEX idx_lab_work_order_cabinet_expected_return
    ON lab_work_order (cabinet_id, expected_return_at);

COMMENT ON COLUMN lab_work_order.shipped_at IS
    'Date d''expédition par le laboratoire (#7209).';
COMMENT ON COLUMN lab_work_order.received_at IS
    'Date de réception au cabinet (#7209).';
COMMENT ON COLUMN lab_work_order.tracking_ref IS
    'Référence de suivi transporteur, libre (#7209).';

COMMENT ON TABLE lab_work_order IS
    'Bon de travail prothétique envoyé à un laboratoire (statut sent/try_in/returned/fitted/in_progress/shipped/received), prix d''achat obligatoire. #4147, #7209.';
