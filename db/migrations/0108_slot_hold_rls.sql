-- 0108_slot_hold_rls.sql
-- Isolation cabinet sur slot_holds via availability_slot.cabinet_id (transitive).
-- Migration 0095 avait posé ENABLE+FORCE RLS avec une policy permissive slot_holds_app
-- (USING(true)). Cette migration remplace slot_holds_app par slot_hold_cabinet_isolation :
-- un cabinet ne voit que les holds portant sur ses propres créneaux.
-- GUC absent → nullif(...)::uuid = NULL → EXISTS = false → fail-closed.
-- Issue : #2447

DROP POLICY slot_holds_app ON slot_holds;

CREATE POLICY slot_hold_cabinet_isolation ON slot_holds
  FOR ALL TO nubia_app
  USING (
    EXISTS (
      SELECT 1 FROM availability_slot
      WHERE id         = slot_holds.slot_id
        AND cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid
    )
  );
