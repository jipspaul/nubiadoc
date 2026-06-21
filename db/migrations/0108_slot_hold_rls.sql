-- 0108_slot_hold_rls.sql
-- Isolation cabinet sur slot_holds : policy restrictive (FOR SELECT, nubia_app)
-- via jointure transitive sur availability_slot.cabinet_id.
-- slot_holds n'a pas de cabinet_id direct (table plateforme marketplace) ;
-- la vérification passe par le créneau détenu → cabinet propriétaire du créneau.
-- Réf. : issue #2447 (DB-T025).
--
-- Avant cette migration :
--   slot_holds_app  : PERMISSIVE FOR ALL USING(true)  → toutes les lignes visibles.
--   slot_holds_seed : PERMISSIVE FOR ALL USING(true)  → toutes les lignes visibles.
-- Après cette migration :
--   slot_hold_cabinet_isolation : RESTRICTIVE FOR SELECT TO nubia_app
--     → nubia_app ne voit QUE les holds dont le slot appartient au cabinet GUC.
--     → GUC absent → nullif(...)::uuid = NULL → EXISTS = false → 0 ligne (fail-closed).
--   nubia_seed conserve la visibilité totale (seed démo uniquement).

CREATE POLICY slot_hold_cabinet_isolation ON slot_holds
  AS RESTRICTIVE
  FOR SELECT TO nubia_app
  USING (
    EXISTS (
      SELECT 1 FROM availability_slot
       WHERE id         = slot_holds.slot_id
         AND cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
    )
  );
