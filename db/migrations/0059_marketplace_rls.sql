-- 0059_marketplace_rls.sql
-- RLS publique pour availability_slot et review (marketplace).
-- Réf. : issue #825 ; docs/05 §9.2-§9.3 ; docs/12 §12.4.
--
-- Modèle :
--   availability_slot → lecture publique des slots 'open' (réservation marketplace).
--   review            → lecture publique des avis 'published' (annuaire).
-- Ces tables n'ont PAS de cabinet_id tenant → pas de policy cabinet.
-- La restriction porte sur le STATUT : seuls les enregistrements en état public
-- sont lisibles sans contexte (pas de fail-closed sur le GUC cabinet).
--
-- nubia_app : INSERT libre (réservation de slot, soumission d'avis). UPDATE pour
--   les transitions de statut (held→open, pending→published/rejected). SELECT
--   soumis aux mêmes règles de lecture publique que les autres rôles (status filter).
-- nubia_seed : accès complet (données de démo fictives).

-- ---------------------------------------------------------------------------
-- availability_slot
-- ---------------------------------------------------------------------------
ALTER TABLE availability_slot ENABLE ROW LEVEL SECURITY;
ALTER TABLE availability_slot FORCE ROW LEVEL SECURITY;

-- Lecture publique : seuls les créneaux ouverts sont visibles (annuaire / marketplace).
-- S'applique à tous les rôles y.c. nubia_app (SELECT borné au statut 'open').
CREATE POLICY slot_public_read ON availability_slot
  FOR SELECT
  USING (status = 'open');

-- nubia_app : INSERT libre (création d'un créneau par un cabinet/provider).
CREATE POLICY slot_app_insert ON availability_slot
  FOR INSERT TO nubia_app
  WITH CHECK (true);

-- nubia_app : UPDATE libre (transition de statut : open→held→booked, annulation).
CREATE POLICY slot_app_update ON availability_slot
  FOR UPDATE TO nubia_app
  USING (true)
  WITH CHECK (true);

-- nubia_seed : accès complet (données de démo fictives).
CREATE POLICY slot_seed ON availability_slot
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);

-- ---------------------------------------------------------------------------
-- review
-- ---------------------------------------------------------------------------
ALTER TABLE review ENABLE ROW LEVEL SECURITY;
ALTER TABLE review FORCE ROW LEVEL SECURITY;

-- Lecture publique : seuls les avis publiés (modérés) sont visibles.
-- S'applique à tous les rôles y.c. nubia_app.
CREATE POLICY review_public_read ON review
  FOR SELECT
  USING (status = 'published');

-- nubia_app : INSERT libre (soumission d'un avis par un patient).
CREATE POLICY review_app_insert ON review
  FOR INSERT TO nubia_app
  WITH CHECK (true);

-- nubia_app : UPDATE libre (modération : pending→published/rejected).
CREATE POLICY review_app_update ON review
  FOR UPDATE TO nubia_app
  USING (true)
  WITH CHECK (true);

-- nubia_seed : accès complet (données de démo fictives).
CREATE POLICY review_seed ON review
  FOR ALL TO nubia_seed
  USING (true) WITH CHECK (true);
