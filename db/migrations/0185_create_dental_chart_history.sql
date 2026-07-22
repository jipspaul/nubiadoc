-- 0185_create_dental_chart_history.sql
-- Historisation de l'odontogramme (#4121) : `dental_chart` fait un UPSERT
-- qui écrase `teeth_status` à chaque PUT (migration 0080 impose une seule
-- ligne par patient/cabinet) — impossible de reconstituer l'état
-- bucco-dentaire à une date passée.
--
-- dental_chart_history : append-only (comme audit_log, migration 0011) —
-- seuls INSERT/SELECT sont accordés à nubia_app, aucun UPDATE/DELETE, pour
-- qu'un snapshot historique ne puisse jamais être modifié après coup.
-- teeth_status NOT NULL sans DEFAULT '{}' : contrairement à dental_chart,
-- une ligne d'historique n'a de sens que si elle capture un état réel
-- (jamais créée vide).

CREATE TABLE dental_chart_history (
    id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id   uuid        NOT NULL REFERENCES cabinet(id),
    patient_id   uuid        NOT NULL REFERENCES patient(id),
    teeth_status jsonb       NOT NULL,
    recorded_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_dental_chart_history_patient
    ON dental_chart_history (patient_id, recorded_at DESC);

ALTER TABLE dental_chart_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE dental_chart_history FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON dental_chart_history
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

-- Append-only : ni UPDATE ni DELETE côté application (même garde qu'audit_log,
-- migrations 0008/0011). ALTER DEFAULT PRIVILEGES (migration 0001) accorde
-- SELECT/INSERT/UPDATE/DELETE à nubia_app sur toute nouvelle table — un simple
-- GRANT plus restrictif ne retire rien, il faut explicitement REVOKE ALL
-- d'abord (sinon UPDATE/DELETE resteraient silencieusement autorisés).
REVOKE ALL ON dental_chart_history FROM nubia_app;
GRANT SELECT, INSERT ON dental_chart_history TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON dental_chart_history TO nubia_seed;

COMMENT ON TABLE dental_chart_history IS
    'Snapshot de teeth_status avant chaque écrasement par PUT /dental-chart. Append-only. #4121.';
