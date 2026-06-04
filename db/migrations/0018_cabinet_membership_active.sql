-- 0018_cabinet_membership_active.sql
-- Ajoute la colonne active (flag membre actif/inactif) à cabinet_membership.
-- Issue : #207

ALTER TABLE cabinet_membership
  ADD COLUMN IF NOT EXISTS active BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN cabinet_membership.active IS 'Membre actif dans ce cabinet (false = révocation sans suppression, soft-disable).';
