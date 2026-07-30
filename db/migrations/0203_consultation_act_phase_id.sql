-- 0203_consultation_act_phase_id.sql
-- consultation_act.phase_id (#4120) : rattache optionnellement un acte de
-- séance à une treatment_phase (typiquement une phase avec
-- planned_sessions renseigné, migration 0184 — ex. "10 séances de suivi
-- orthodontique") pour que POST .../consultations/:id/complete puisse
-- incrémenter completed_sessions de la phase concernée.
--
-- FK composite (phase_id, cabinet_id) dès la création, pas une FK simple à
-- corriger après coup — même gap RLS-bypass documenté dans #4291/0200 :
-- treatment_phase a déjà UNIQUE(id, cabinet_id) depuis la migration 0200,
-- réutilisée ici directement.

ALTER TABLE consultation_act
    ADD COLUMN phase_id uuid;

ALTER TABLE consultation_act
    ADD CONSTRAINT consultation_act_phase_id_cabinet_fkey
    FOREIGN KEY (phase_id, cabinet_id)
    REFERENCES treatment_phase (id, cabinet_id);

CREATE INDEX consultation_act_phase_idx
    ON consultation_act (phase_id) WHERE phase_id IS NOT NULL;

COMMENT ON COLUMN consultation_act.phase_id IS
    'Phase de traitement à laquelle cet acte se rattache (ex. suivi orthodontique/parodontal à séances programmées). NULL = acte hors mécanisme de décompte. #4120.';
