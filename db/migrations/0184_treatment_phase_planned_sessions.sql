-- 0184_treatment_phase_planned_sessions.sql
-- Séances programmées sur treatment_phase (#4119) : aucune structure ne
-- permet de préprogrammer une série de séances facturées automatiquement
-- (utile ortho/parodonto — ex. "10 séances de suivi orthodontique").
--
-- planned_sessions nullable (pas de valeur par défaut) : une phase qui
-- n'utilise pas ce mécanisme (cas actuel de toutes les phases existantes)
-- n'a pas de nombre de séances programmées, distinct de "0 séance prévue"
-- qui serait une valeur métier fausse. completed_sessions démarre à 0
-- (compteur, jamais NULL — une phase sans séance programmée a par
-- construction 0 séance complétée dans ce mécanisme).
--
-- CHECK completed_sessions <= planned_sessions seulement quand
-- planned_sessions est renseigné (sinon la comparaison serait toujours vraie
-- via IS NULL, mais on l'exprime explicitement pour la lisibilité).

ALTER TABLE treatment_phase
  ADD COLUMN planned_sessions   integer,
  ADD COLUMN completed_sessions integer NOT NULL DEFAULT 0,
  ADD CONSTRAINT treatment_phase_planned_sessions_positive
    CHECK (planned_sessions IS NULL OR planned_sessions > 0),
  ADD CONSTRAINT treatment_phase_completed_sessions_non_negative
    CHECK (completed_sessions >= 0),
  ADD CONSTRAINT treatment_phase_completed_not_over_planned
    CHECK (planned_sessions IS NULL OR completed_sessions <= planned_sessions);

COMMENT ON COLUMN treatment_phase.planned_sessions IS
    'Nombre de séances programmées pour cette phase (ex. suivi ortho/parodonto). NULL = mécanisme non utilisé. #4119.';
COMMENT ON COLUMN treatment_phase.completed_sessions IS
    'Nombre de séances déjà réalisées parmi planned_sessions. #4119.';
