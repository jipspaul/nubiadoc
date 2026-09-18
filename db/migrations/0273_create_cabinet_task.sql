-- 0273_create_cabinet_task.sql
-- Tâches internes assignables du cabinet (#7212) : to-do secrétariat et notes
-- à l'assistante depuis un RDV. Aucune table de tâches n'existait jusqu'ici.
--
-- cabinet_task : titre + description libres, assignee optionnel (membre du
-- cabinet), patient/RDV optionnels (une note peut être détachée de tout
-- contexte), échéance optionnelle, statut, créateur.
--
-- FK COMPOSITES (assignee_user_id, cabinet_id) / (patient_id, cabinet_id) /
-- (appointment_id, cabinet_id) plutôt que des FK simples sur l'id seul :
-- PostgreSQL fait bypasser la RLS aux vérifications d'intégrité
-- référentielle (FK/UNIQUE/PK) même sous FORCE ROW LEVEL SECURITY — cf.
-- #4137/migration 0190, réutilisé par lab_work_order (migration 0193).
-- patient/appointment ont déjà UNIQUE (id, cabinet_id) depuis la migration
-- 0193 ; cabinet_membership a UNIQUE (cabinet_id, user_id) depuis la
-- migration 0002 — réutilisée ici pour garantir qu'un assignee appartient
-- bien au cabinet de la tâche.

CREATE TABLE cabinet_task (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id        uuid        NOT NULL REFERENCES cabinet(id),
    title             text        NOT NULL,
    description       text,
    assignee_user_id  uuid,
    patient_id        uuid,
    appointment_id    uuid,
    due_date          date,
    status            text        NOT NULL DEFAULT 'open'
                                   CHECK (status IN ('open', 'done', 'cancelled')),
    created_by        uuid        NOT NULL REFERENCES app_user(id),
    created_at        timestamptz NOT NULL DEFAULT now(),
    done_at           timestamptz,
    CONSTRAINT cabinet_task_title_not_blank CHECK (btrim(title) <> ''),
    FOREIGN KEY (cabinet_id, assignee_user_id)
        REFERENCES cabinet_membership (cabinet_id, user_id),
    FOREIGN KEY (patient_id, cabinet_id)
        REFERENCES patient (id, cabinet_id),
    FOREIGN KEY (appointment_id, cabinet_id)
        REFERENCES appointment (id, cabinet_id)
);

-- Index tenant-first : liste de tâches d'un cabinet filtrée par statut,
-- triée par échéance (vue to-do secrétariat).
CREATE INDEX idx_cabinet_task_cabinet_status_due
    ON cabinet_task (cabinet_id, status, due_date);

GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_task TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_task TO nubia_seed;

-- RLS : isolation par cabinet (fail-closed : GUC absent → 0 ligne).
ALTER TABLE cabinet_task ENABLE ROW LEVEL SECURITY;
ALTER TABLE cabinet_task FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON cabinet_task
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE cabinet_task IS
    'Tâches internes assignables du cabinet (to-do secrétariat, notes depuis un RDV). Statut open/done/cancelled. Table tenant (cabinet_id). RLS fail-closed. #7212.';
