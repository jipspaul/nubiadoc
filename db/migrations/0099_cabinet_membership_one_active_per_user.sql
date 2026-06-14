-- 0099_cabinet_membership_one_active_per_user.sql
-- Enforcer l'invariant : un user_id ne peut pas être membre actif
-- (active = true AND left_at IS NULL) de plus d'un cabinet simultanément.
-- Réf. : issue #1829 (T-DB-D003), docs/05 §5.1.
--
-- Le UNIQUE (cabinet_id, user_id) existant (0002) empêche les doublons
-- par cabinet, mais ne couvre pas la multi-appartenance active inter-cabinets.
-- Un index unique partiel sur user_id WHERE active = true AND left_at IS NULL
-- enforce cette règle au niveau base.

CREATE UNIQUE INDEX cabinet_membership_one_active_per_user
  ON cabinet_membership (user_id)
  WHERE active = true AND left_at IS NULL;

COMMENT ON INDEX cabinet_membership_one_active_per_user IS
  'Un user ne peut être membre actif (active=true, left_at IS NULL) que d''un seul cabinet à la fois.';
