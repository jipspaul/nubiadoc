-- 0173_appointment_recurrence.sql
-- Regroupement de RDV en série (ortho, parodonto, chirurgie multi-séances,
-- #4087) : deux colonnes nullables sur `appointment`, sans toucher la
-- contrainte d'exclusion anti-double-booking existante (`appointment_no_overlap`,
-- migration 0005) — recurrence_id/index sont purement informatifs, ils ne
-- participent à aucune contrainte d'exclusion. Un RDV hors série garde les
-- deux colonnes NULL.
--
-- recurrence_index : position 1-based dans la série (1er RDV = 1, etc.).
-- Les deux colonnes sont NULL ou non-NULL ensemble (CHECK pairée) — un
-- recurrence_id sans index (ou l'inverse) n'a pas de sens métier.

ALTER TABLE appointment
    ADD COLUMN recurrence_id uuid,
    ADD COLUMN recurrence_index integer;

ALTER TABLE appointment
    ADD CONSTRAINT appointment_recurrence_pair_chk
        CHECK ((recurrence_id IS NULL) = (recurrence_index IS NULL)),
    ADD CONSTRAINT appointment_recurrence_index_positive_chk
        CHECK (recurrence_index IS NULL OR recurrence_index >= 1);

CREATE INDEX idx_appointment_recurrence
    ON appointment (recurrence_id)
    WHERE recurrence_id IS NOT NULL;

COMMENT ON COLUMN appointment.recurrence_id IS 'Regroupe les RDV d''une même série (ortho, parodonto, chirurgie multi-séances) — NULL si RDV isolé. Issue #4087.';
COMMENT ON COLUMN appointment.recurrence_index IS 'Position 1-based du RDV dans sa série (recurrence_id). NULL si RDV isolé — toujours NULL/non-NULL en phase avec recurrence_id.';
