-- 0099_cabinet_membership_one_active_per_user.sql
-- Enforcer l'invariant : un user_id ne peut pas être membre actif
-- (active = true AND left_at IS NULL) de plus d'un cabinet simultanément.
-- Réf. : issue #1829 (T-DB-D003), docs/05 §5.1.
--
-- Le UNIQUE (cabinet_id, user_id) existant (0002) empêche les doublons
-- par cabinet, mais ne couvre pas la multi-appartenance active inter-cabinets.
-- Un index unique partiel sur user_id WHERE active = true AND left_at IS NULL
-- enforce cette règle au niveau base.
--
-- HISTORIQUE — la version initiale créait directement l'index, ce qui plantait
-- sur tout env où les données seed violaient déjà l'invariant. Comme cette
-- migration n'a JAMAIS réussi à s'appliquer ailleurs (failed depuis l'origine),
-- on peut sans risque la réécrire pour inclure un backfill préalable avant
-- l'index. La règle forward-only protège l'historique des migrations
-- SUCCESSFULLY APPLIED — ici aucun checksum mismatch possible.

-- 1. Backfill : pour chaque user_id avec >1 membership active, on garde la
--    PLUS RÉCEMMENT créée (max created_at) et on soft-disable les autres
--    (left_at = now(), active = false). C'est conforme à la sémantique métier
--    de soft-revocation (cf. col `active` 0018, col `left_at` 0022).
DO $$
DECLARE
  dup_count int := 0;
BEGIN
  WITH dups AS (
    SELECT user_id
    FROM cabinet_membership
    WHERE active = true AND left_at IS NULL
    GROUP BY user_id
    HAVING count(*) > 1
  ),
  winners AS (
    SELECT DISTINCT ON (cm.user_id)
      cm.user_id, cm.cabinet_id
    FROM cabinet_membership cm
    JOIN dups d ON d.user_id = cm.user_id
    WHERE cm.active = true AND cm.left_at IS NULL
    ORDER BY cm.user_id, cm.created_at DESC, cm.id DESC
  )
  UPDATE cabinet_membership cm
  SET active = false,
      left_at = now()
  FROM winners w
  WHERE cm.user_id = w.user_id
    AND cm.cabinet_id <> w.cabinet_id
    AND cm.active = true
    AND cm.left_at IS NULL;

  GET DIAGNOSTICS dup_count = ROW_COUNT;
  IF dup_count > 0 THEN
    RAISE NOTICE '0099 backfill: % rows soft-disabled (multi-cabinet active memberships).', dup_count;
  END IF;
END $$;

-- 2. Index unique partiel (idempotent : IF NOT EXISTS si la première version
--    avait quand même réussi à le créer ailleurs avant ce rewrite).
CREATE UNIQUE INDEX IF NOT EXISTS cabinet_membership_one_active_per_user
  ON cabinet_membership (user_id)
  WHERE active = true AND left_at IS NULL;

COMMENT ON INDEX cabinet_membership_one_active_per_user IS
  'Un user ne peut être membre actif (active=true, left_at IS NULL) que d''un seul cabinet à la fois.';
