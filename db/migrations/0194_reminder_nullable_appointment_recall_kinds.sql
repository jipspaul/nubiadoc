-- 0194_reminder_nullable_appointment_recall_kinds.sql
-- Campagnes de rappel sans RDV associé (#4150) : reminder imposait
-- appointment_id NOT NULL et kind IN ('rdv_rappel', 'rdv_confirmation',
-- 'rdv_follow_up'), ce qui empêchait toute campagne de contrôle annuel/
-- détartrage pour un patient sans RDV à venir.
--
-- reminder a déjà son propre cabinet_id (migration 0085, indépendant
-- d'appointment_id) et sa propre policy RLS tenant_isolation filtrant sur
-- ce cabinet_id — rendre appointment_id nullable n'introduit donc AUCUN
-- trou RLS : un rappel de campagne (appointment_id NULL) reste
-- cabinet-scopé via son propre cabinet_id, et patient-scopé (policy
-- reminder_patient_read, migration 0171) via patient_id (resté NOT NULL).
-- due_reminders_for_dispatch() (migrations 0156/0157) joint déjà via
-- patient_id, pas via appointment_id — inchangé.

ALTER TABLE reminder
    ALTER COLUMN appointment_id DROP NOT NULL;

ALTER TABLE reminder
    DROP CONSTRAINT reminder_kind_check;
ALTER TABLE reminder
    ADD CONSTRAINT reminder_kind_check
    CHECK (kind IN ('rdv_rappel', 'rdv_confirmation', 'rdv_follow_up', 'recall_annual', 'recall_detartrage'));
