-- 01_constraints.sql — Les contraintes REJETTENT les mauvaises valeurs.
-- CHECK / NOT NULL / UNIQUE / EXCLUDE (anti-double-booking). pgTAP, sous nubia_app.
BEGIN;
SELECT * FROM no_plan();

-- Fixtures minimales dans le cabinet A (RLS : on pose le contexte tenant).
SET LOCAL app.current_cabinet_id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES ('a0000000-0000-0000-0000-000000000001','Cabinet A');
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('a0000000-0000-0000-0000-0000000000a1','prat.a@example.test','$argon2id$fixture','pro');
INSERT INTO practitioner (id, cabinet_id, user_id)
  VALUES ('a0000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000a1');
INSERT INTO patient (id, cabinet_id, first_name, last_name)
  VALUES ('a0000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','Marc','Dubois');

-- ----- CHECK : valeurs d'énumération invalides rejetées -----
SELECT throws_ok(
  $$ INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256)
     VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000d1',
             'pas_une_categorie','k','f.pdf','application/pdf', repeat('0',64)) $$,
  '23514', NULL, 'document.category invalide rejeté (CHECK)');

SELECT throws_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000d1',
             'a0000000-0000-0000-0000-0000000000c1','2026-06-10 09:00+00','2026-06-10 09:30+00','farfelu') $$,
  '23514', NULL, 'appointment.status invalide rejeté (CHECK)');

SELECT throws_ok(
  $$ INSERT INTO cabinet_membership (cabinet_id, user_id, role)
     VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000a1','root') $$,
  '23514', NULL, 'cabinet_membership.role invalide rejeté (CHECK)');

-- ----- UNIQUE : (cabinet_id, user_id) — un user ne peut être membre qu'une fois par cabinet -----
INSERT INTO cabinet_membership (cabinet_id, user_id, role)
  VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000a1','admin');

SELECT throws_ok(
  $$ INSERT INTO cabinet_membership (cabinet_id, user_id, role)
     VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000a1','secretary') $$,
  '23505', NULL, 'cabinet_membership (cabinet_id, user_id) dupliqué rejeté (UNIQUE)');

-- ----- CHECK : ordre temporel du RDV -----
SELECT throws_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000d1',
             'a0000000-0000-0000-0000-0000000000c1','2026-06-10 10:00+00','2026-06-10 09:00+00','confirmed') $$,
  '23514', NULL, 'appointment ends_at <= starts_at rejeté (CHECK)');

-- ----- CHECK : paire de chiffrement cohérente -----
SELECT throws_ok(
  $$ INSERT INTO patient (cabinet_id, first_name, last_name, ins_ciphertext)
     VALUES ('a0000000-0000-0000-0000-000000000001','X','Y','\x00') $$,
  '23514', NULL, 'patient ins_ciphertext sans key_ref rejeté (CHECK paire crypto)');

-- ----- NOT NULL : contenu chiffré obligatoire -----
SELECT throws_ok(
  $$ INSERT INTO clinical_note (cabinet_id, patient_id, author_id, content_key_ref)
     VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000d1',
             'a0000000-0000-0000-0000-0000000000a1','k1') $$,
  '23502', NULL, 'clinical_note.content_ciphertext NOT NULL rejette NULL');

-- ----- UNIQUE : email app_user -----
SELECT throws_ok(
  $$ INSERT INTO app_user (email, password_hash, kind) VALUES ('prat.a@example.test','$h$','pro') $$,
  '23505', NULL, 'app_user.email dupliqué rejeté (UNIQUE, citext)');

-- citext : insensible à la casse -> collision sur la casse différente
SELECT throws_ok(
  $$ INSERT INTO app_user (email, password_hash, kind) VALUES ('PRAT.A@EXAMPLE.TEST','$h$','pro') $$,
  '23505', NULL, 'app_user.email collision casse (citext)');

-- ----- ⭐ EXCLUDE : anti-double-booking praticien -----
INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000d1',
          'a0000000-0000-0000-0000-0000000000c1','2026-06-10 10:00+00','2026-06-10 10:30+00','confirmed');

SELECT throws_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000d1',
             'a0000000-0000-0000-0000-0000000000c1','2026-06-10 10:15+00','2026-06-10 10:45+00','confirmed') $$,
  '23P01', NULL, '⭐ RDV chevauchant rejeté (EXCLUDE gist)');

-- créneau adjacent (pas de chevauchement) -> accepté
SELECT lives_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000d1',
             'a0000000-0000-0000-0000-0000000000c1','2026-06-10 10:30+00','2026-06-10 11:00+00','confirmed') $$,
  'RDV adjacent (10:30-11:00) accepté');

-- chevauchement mais statut cancelled -> accepté (clause WHERE de l'EXCLUDE)
SELECT lives_ok(
  $$ INSERT INTO appointment (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status)
     VALUES ('a0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000d1',
             'a0000000-0000-0000-0000-0000000000c1','2026-06-10 10:10+00','2026-06-10 10:20+00','cancelled') $$,
  'RDV chevauchant mais cancelled accepté (hors EXCLUDE)');

-- ----- CHECK : note review 1..5 -----
-- app_user 'patient' requis depuis 0015 (app_user_id NOT NULL)
INSERT INTO app_user (id, email, password_hash, kind)
  VALUES ('a0000000-0000-0000-0000-0000000000a2','patient.a@example.test','$argon2id$fixture','patient');
INSERT INTO patient_account (id, app_user_id, first_name, last_name)
  VALUES ('a0000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000a2','Marc','Dubois');
INSERT INTO provider (id, cabinet_id, display_name, is_listed)
  VALUES ('a0000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000001','Dr A', true);
SELECT throws_ok(
  $$ INSERT INTO review (provider_id, patient_account_id, rating)
     VALUES ('a0000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-0000000000e1', 9) $$,
  '23514', NULL, 'review.rating hors 1..5 rejeté (CHECK)');

SELECT * FROM finish();
ROLLBACK;
