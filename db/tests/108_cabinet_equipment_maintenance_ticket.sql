-- 108_cabinet_equipment_maintenance_ticket.sql
-- pgTAP : cabinet_equipment / maintenance_ticket / maintenance_ticket_photo
-- (migration 0291, #7168).
--   ME1.  Cabinet A crée un cabinet_equipment (autoclave) OK.
--   ME2.  label vide (après trim) refusé (23514).
--   ME3.  Cabinet A crée un maintenance_ticket rattaché à l'équipement OK.
--   ME4.  priority hors énumération refusée (23514).
--   ME5.  status hors énumération refusé (23514).
--   ME6.  maintenance_ticket_resolved_consistency : status='resolved' sans resolved_at refusé (23514).
--   ME7.  Rattacher un equipment_id d'un AUTRE cabinet refusé (23503).
--   ME8.  Cabinet A rattache une photo (document) au ticket OK.
--   ME9.  Rattacher un document d'un AUTRE cabinet refusé (23503).
--   ME10. RLS cabinet_equipment : cabinet B ne voit pas l'équipement de A.
--   ME11. RLS maintenance_ticket : cabinet B ne voit pas le ticket de A.
--   ME12. RLS maintenance_ticket_photo : cabinet B ne voit pas la photo de A.
--   ME13. Fail-closed : sans GUC → 0 ligne sur les trois tables.
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 71680000.
-- Issue : #7168

BEGIN;
SELECT plan(13);

-- ===========================================================================
-- Fixtures : 2 cabinets. Cabinet A avec app_user (déclarant) + document.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71680000-0000-0000-0000-000000000c01';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71680000-0000-0000-0000-000000000c01', 'Cabinet Equipment-7168-A');
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71680000-0000-0000-0000-000000000a01', 'secretaire.7168@nubia.test', '$argon2id$fixture', 'pro');
INSERT INTO document (id, cabinet_id, category, storage_key, filename, mime_type, sha256) VALUES
  ('71680000-0000-0000-0000-00000000d001', '71680000-0000-0000-0000-000000000c01',
   'photo', 'maintenance/7168/a01.jpg', 'panne.jpg', 'image/jpeg', repeat('b', 64));
RESET app.current_cabinet_id;

SET LOCAL app.current_cabinet_id = '71680000-0000-0000-0000-000000000c02';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('71680000-0000-0000-0000-000000000c02', 'Cabinet Equipment-7168-B');
RESET app.current_cabinet_id;

-- ===========================================================================
-- ME1. Cabinet A crée un cabinet_equipment (autoclave) OK.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71680000-0000-0000-0000-000000000c01';
INSERT INTO cabinet_equipment (id, cabinet_id, label, category, room, supplier, technician_email, technician_phone, purchased_at, next_check_at) VALUES
  ('71680000-0000-0000-0000-000000005e01', '71680000-0000-0000-0000-000000000c01',
   'Autoclave Classe B', 'autoclave', 'Salle de stérilisation', 'Sterident',
   'sav@sterident.example', '+33100000000', '2024-03-01', '2027-03-01');
SELECT is(
  (SELECT count(*)::int FROM cabinet_equipment
   WHERE id = '71680000-0000-0000-0000-000000005e01'),
  1,
  'ME1 cabinet_equipment : création cabinet A, autoclave OK');

-- ===========================================================================
-- ME2. label vide (après trim) refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO cabinet_equipment (cabinet_id, label, category)
     VALUES ('71680000-0000-0000-0000-000000000c01', '   ', 'fauteuil') $$,
  '23514', NULL,
  'ME2 cabinet_equipment_label_not_blank : label vide refusé (23514)');

-- ===========================================================================
-- ME3. Cabinet A crée un maintenance_ticket rattaché à l'équipement OK.
-- ===========================================================================
INSERT INTO maintenance_ticket (id, cabinet_id, equipment_id, title, description, priority, status, reported_by, assigned_to_email) VALUES
  ('71680000-0000-0000-0000-000000006f01', '71680000-0000-0000-0000-000000000c01',
   '71680000-0000-0000-0000-000000005e01', 'Fuite vapeur autoclave', 'Fuite au niveau du joint de porte',
   'high', 'open', '71680000-0000-0000-0000-000000000a01', 'sav@sterident.example');
SELECT is(
  (SELECT count(*)::int FROM maintenance_ticket
   WHERE id = '71680000-0000-0000-0000-000000006f01'),
  1,
  'ME3 maintenance_ticket : création cabinet A, ticket rattaché à l''équipement OK');

-- ===========================================================================
-- ME4. priority hors énumération refusée.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO maintenance_ticket (cabinet_id, title, priority, reported_by)
     VALUES ('71680000-0000-0000-0000-000000000c01', 'Ticket invalide', 'critical',
             '71680000-0000-0000-0000-000000000a01') $$,
  '23514', NULL,
  'ME4 maintenance_ticket_priority_check : priority hors énumération refusée (23514)');

-- ===========================================================================
-- ME5. status hors énumération refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO maintenance_ticket (cabinet_id, title, status, reported_by)
     VALUES ('71680000-0000-0000-0000-000000000c01', 'Ticket invalide', 'closed',
             '71680000-0000-0000-0000-000000000a01') $$,
  '23514', NULL,
  'ME5 maintenance_ticket_status_check : status hors énumération refusé (23514)');

-- ===========================================================================
-- ME6. maintenance_ticket_resolved_consistency : status=resolved sans
-- resolved_at refusé.
-- ===========================================================================
SELECT throws_ok(
  $$ INSERT INTO maintenance_ticket (cabinet_id, title, status, reported_by)
     VALUES ('71680000-0000-0000-0000-000000000c01', 'Ticket résolu sans date', 'resolved',
             '71680000-0000-0000-0000-000000000a01') $$,
  '23514', NULL,
  'ME6 maintenance_ticket_resolved_consistency : status=resolved sans resolved_at refusé (23514)');

-- ===========================================================================
-- ME7. Rattacher un equipment_id d'un AUTRE cabinet refusé (23503).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71680000-0000-0000-0000-000000000c02';
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('71680000-0000-0000-0000-000000000a02', 'secretaire.7168b@nubia.test', '$argon2id$fixture', 'pro');
SELECT throws_ok(
  $$ INSERT INTO maintenance_ticket (cabinet_id, equipment_id, title, reported_by)
     VALUES ('71680000-0000-0000-0000-000000000c02',
             '71680000-0000-0000-0000-000000005e01',
             'Ticket cross-tenant', '71680000-0000-0000-0000-000000000a02') $$,
  '23503', NULL,
  '⭐ ME7 maintenance_ticket : rattacher un equipment_id d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- ME8. Cabinet A rattache une photo (document) au ticket OK.
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71680000-0000-0000-0000-000000000c01';
INSERT INTO maintenance_ticket_photo (id, cabinet_id, ticket_id, document_id) VALUES
  ('71680000-0000-0000-0000-000000007a01', '71680000-0000-0000-0000-000000000c01',
   '71680000-0000-0000-0000-000000006f01', '71680000-0000-0000-0000-00000000d001');
SELECT is(
  (SELECT count(*)::int FROM maintenance_ticket_photo
   WHERE id = '71680000-0000-0000-0000-000000007a01'),
  1,
  'ME8 maintenance_ticket_photo : rattachement photo cabinet A OK');

-- ===========================================================================
-- ME9. Rattacher un document d'un AUTRE cabinet refusé (23503).
-- ===========================================================================
SET LOCAL app.current_cabinet_id = '71680000-0000-0000-0000-000000000c02';
INSERT INTO maintenance_ticket (id, cabinet_id, title, reported_by) VALUES
  ('71680000-0000-0000-0000-000000006f02', '71680000-0000-0000-0000-000000000c02',
   'Ticket cabinet B', '71680000-0000-0000-0000-000000000a02');
SELECT throws_ok(
  $$ INSERT INTO maintenance_ticket_photo (cabinet_id, ticket_id, document_id)
     VALUES ('71680000-0000-0000-0000-000000000c02',
             '71680000-0000-0000-0000-000000006f02',
             '71680000-0000-0000-0000-00000000d001') $$,
  '23503', NULL,
  '⭐ ME9 maintenance_ticket_photo : rattacher un document d''un autre cabinet refusé (23503, RLS FK)');

-- ===========================================================================
-- ME10. RLS cabinet_equipment : cabinet B ne voit PAS l'équipement de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM cabinet_equipment
   WHERE id = '71680000-0000-0000-0000-000000005e01'),
  0,
  '⭐ ME10 tenant_isolation cabinet_equipment : cabinet B ne voit PAS l''équipement de A');

-- ===========================================================================
-- ME11. RLS maintenance_ticket : cabinet B ne voit PAS le ticket de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM maintenance_ticket
   WHERE id = '71680000-0000-0000-0000-000000006f01'),
  0,
  '⭐ ME11 tenant_isolation maintenance_ticket : cabinet B ne voit PAS le ticket de A');

-- ===========================================================================
-- ME12. RLS maintenance_ticket_photo : cabinet B ne voit PAS la photo de A.
-- ===========================================================================
SELECT is(
  (SELECT count(*)::int FROM maintenance_ticket_photo
   WHERE id = '71680000-0000-0000-0000-000000007a01'),
  0,
  '⭐ ME12 tenant_isolation maintenance_ticket_photo : cabinet B ne voit PAS la photo de A');

-- ===========================================================================
-- ME13. Fail-closed : sans GUC → 0 ligne sur les trois tables.
-- ===========================================================================
RESET app.current_cabinet_id;
SELECT is(
  (SELECT count(*)::int FROM cabinet_equipment)
    + (SELECT count(*)::int FROM maintenance_ticket)
    + (SELECT count(*)::int FROM maintenance_ticket_photo),
  0,
  '⭐ ME13 fail-closed : 0 ligne sur les trois tables sans GUC positionné');

SELECT * FROM finish();
ROLLBACK;
