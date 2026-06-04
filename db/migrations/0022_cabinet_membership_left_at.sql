-- 0022_cabinet_membership_left_at.sql
-- Ajoute left_at à cabinet_membership pour tracer la date de révocation (soft-delete).
-- Issue : #226

ALTER TABLE cabinet_membership
  ADD COLUMN IF NOT EXISTS left_at TIMESTAMPTZ;

COMMENT ON COLUMN cabinet_membership.left_at IS 'Date de révocation de l''accès (soft-delete). NULL = membre toujours actif.';
