-- 0098_cabinet_membership_role_manager_doctor.sql
-- Étend le CHECK de cabinet_membership.role pour accepter 'manager' et 'doctor'
-- en plus de 'practitioner', 'secretary' et 'admin'.
-- Réf. : issue #1642 (PLAN-ATOMIC E.2.10).

ALTER TABLE cabinet_membership
  DROP CONSTRAINT IF EXISTS cabinet_membership_role_check;

ALTER TABLE cabinet_membership
  ADD CONSTRAINT cabinet_membership_role_check
    CHECK (role IN ('practitioner', 'secretary', 'admin', 'manager', 'doctor'));
