-- db/seed/seed.sql — Jeu de démo FICTIF, déterministe et rejouable.
-- ⚠️ Données 100 % inventées. AUCUNE PII réelle avant la barrière G3 (docs/07 §11).
-- Chargé par le rôle nubia_seed (NOSUPERUSER, NOBYPASSRLS) -> on POSE le contexte tenant.
--
-- Déterminisme : UUID figés, timestamps littéraux (jamais now()/random()/gen_random_uuid()).
-- Idempotence : ON CONFLICT (id) DO NOTHING (rejouable sans doublon).
--
-- 🔐 Chiffrement : les colonnes *_ciphertext stockent ici un PLACEHOLDER (key_ref =
--    'SEED_PLACEHOLDER') — le vrai chemin de chiffrement passe par le binaire `nubia`
--    (core/crypto), cf. seed/README.md. NE PAS confondre avec du chiffré de prod.
--
-- 🔑 Mots de passe démo : tous les comptes utilisent "Nubia2026!" (argon2id, cf. README.md).

BEGIN;

-- Contexte tenant unique pour toute la démo (Cabinet Lyon).
SET LOCAL app.current_cabinet_id = '11111111-1111-1111-1111-111111111111';

-- =====================================================================
-- Cabinet & établissement géolocalisé (Lyon 2e)
-- =====================================================================
INSERT INTO cabinet (id, raison_sociale, siret, specialite, settings) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Cabinet Lyon', '12345678900012', 'dentaire',
   '{"horaires":{"lun":"09:00-19:00"},"parking":true,"pmr":true,"code_entree":"A12"}')
ON CONFLICT (id) DO NOTHING;

INSERT INTO establishment (id, name, address, geo) VALUES
  ('22222222-2222-2222-2222-222222222222', 'Cabinet Lyon — Bellecour',
   '{"rue":"12 rue de la République","cp":"69002","ville":"Lyon"}',
   ST_SetSRID(ST_MakePoint(4.8320, 45.7600), 4326)::geography)
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Identité & membres (RPPS fictifs)
-- =====================================================================
-- Membres du cabinet (kind='pro') — rôles : practitioner, practitioner, secretary, admin.
-- Mot de passe démo commun : "Nubia2026!" (argon2id, cf. seed/README.md).
-- Hashes déterministes (salt fixe par utilisateur, cf. README.md §Hashes).
INSERT INTO app_user (id, email, password_hash, kind, rpps, status) VALUES
  ('a0000000-0000-0000-0000-0000000000a1', 'hugo.marin@cabinet-lyon.test',
   '$argon2id$v=19$m=4096,t=3,p=1$ZGVtb1NlZWRhMDAwMDAwMQ$9sU+0grAVmhtI2LnUhePBkmBaodHJzHAz9ar4u1XJPU',
   'pro', '10100000001', 'active'),
  ('a0000000-0000-0000-0000-0000000000a2', 'claire.lefevre@cabinet-lyon.test',
   '$argon2id$v=19$m=4096,t=3,p=1$ZGVtb1NlZWRhMDAwMDAwMg$CYHTiXIAmWDKHVDjjodFPRHuJ7OY++96myhsRwqxXm0',
   'pro', '10100000002', 'active'),
  ('a0000000-0000-0000-0000-0000000000a3', 'sonia.accueil@cabinet-lyon.test',
   '$argon2id$v=19$m=4096,t=3,p=1$ZGVtb1NlZWRhMDAwMDAwMw$B32pRAN6Pa5e3R7AvtK4qP6PovusdNY8njh+CvoJGFA',
   'pro', NULL, 'active'),
  ('a0000000-0000-0000-0000-0000000000a4', 'admin@cabinet-lyon.test',
   '$argon2id$v=19$m=4096,t=3,p=1$ZGVtb1NlZWRhMDAwMDAwNA$39TllpW9C+KxsdPWXUJBGkl20Tl/uAULBnTnMjyqx3M',
   'pro', NULL, 'active')
ON CONFLICT (id) DO NOTHING;

-- Comptes patient (portail patient, kind='patient') — 1 par patient_account.
-- Même mot de passe démo "Nubia2026!" pour marc.dubois ; autres comptes = SEED_PLACEHOLDER.
INSERT INTO app_user (id, email, password_hash, kind) VALUES
  ('a0000000-0000-0000-0000-0000000000a5', 'marc.dubois@patient.test',
   '$argon2id$v=19$m=4096,t=3,p=1$ZGVtb1NlZWRhMDAwMDAwNQ$hl5bvWYmEinnXCxoBUp0DxvmgtJERqsyEM48QSses6Y',
   'patient'),
  ('a0000000-0000-0000-0000-0000000000a6', 'leo.dubois@patient.test',      'SEED_PLACEHOLDER', 'patient'),
  ('a0000000-0000-0000-0000-0000000000a7', 'jade.dubois@patient.test',     'SEED_PLACEHOLDER', 'patient'),
  ('a0000000-0000-0000-0000-0000000000a8', 'camille.rousseau@patient.test','SEED_PLACEHOLDER', 'patient'),
  ('a0000000-0000-0000-0000-0000000000a9', 'karim.saidi@patient.test',     'SEED_PLACEHOLDER', 'patient')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cabinet_membership (id, cabinet_id, user_id, role, active) VALUES
  ('b0000000-0000-0000-0000-0000000000b1','11111111-1111-1111-1111-111111111111','a0000000-0000-0000-0000-0000000000a1','practitioner', true),
  ('b0000000-0000-0000-0000-0000000000b2','11111111-1111-1111-1111-111111111111','a0000000-0000-0000-0000-0000000000a2','practitioner', true),
  ('b0000000-0000-0000-0000-0000000000b3','11111111-1111-1111-1111-111111111111','a0000000-0000-0000-0000-0000000000a3','secretary', true),
  ('b0000000-0000-0000-0000-0000000000b4','11111111-1111-1111-1111-111111111111','a0000000-0000-0000-0000-0000000000a4','admin', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO practitioner (id, cabinet_id, user_id, rpps, specialite) VALUES
  ('c0000000-0000-0000-0000-0000000000c1','11111111-1111-1111-1111-111111111111','a0000000-0000-0000-0000-0000000000a1','10100000001','Chirurgie orale'),
  ('c0000000-0000-0000-0000-0000000000c2','11111111-1111-1111-1111-111111111111','a0000000-0000-0000-0000-0000000000a2','10100000002','Omnipratique')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Annuaire public : professions / spécialités / actes
-- =====================================================================
INSERT INTO profession (id, label) VALUES
  ('d1000000-0000-0000-0000-000000000001','Chirurgien-dentiste')
ON CONFLICT (id) DO NOTHING;
INSERT INTO specialty (id, profession_id, label) VALUES
  ('d2000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','Omnipratique'),
  ('d2000000-0000-0000-0000-000000000002','d1000000-0000-0000-0000-000000000001','Implantologie')
ON CONFLICT (id) DO NOTHING;
INSERT INTO medical_act (id, specialty_id, label, motifs) VALUES
  ('d3000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000001','Détartrage', ARRAY['controle','hygiene']),
  ('d3000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000002','Pose d''implant', ARRAY['implant','dent manquante'])
ON CONFLICT (id) DO NOTHING;

-- Profils provider (listés car RPPS vérifié) + créneaux ouverts + vérification
INSERT INTO provider (id, practitioner_id, cabinet_id, user_id, establishment_id, display_name,
                      rpps, rpps_verified, specialty_id, sector, languages, pmr,
                      teleconsult, accepts_new_patients, geo, rating_avg, rating_count, is_listed) VALUES
  ('f0000000-0000-0000-0000-0000000000f1','c0000000-0000-0000-0000-0000000000c1','11111111-1111-1111-1111-111111111111',
   'a0000000-0000-0000-0000-0000000000a1','22222222-2222-2222-2222-222222222222','Dr Hugo Marin','10100000001', true,
   'd2000000-0000-0000-0000-000000000002','1', ARRAY['fr','en'], true, true, true,
   ST_SetSRID(ST_MakePoint(4.8320,45.7600),4326)::geography, 4.8, 124, true),
  ('f0000000-0000-0000-0000-0000000000f2','c0000000-0000-0000-0000-0000000000c2','11111111-1111-1111-1111-111111111111',
   'a0000000-0000-0000-0000-0000000000a2','22222222-2222-2222-2222-222222222222','Dr Claire Lefèvre','10100000002', true,
   'd2000000-0000-0000-0000-000000000001','2', ARRAY['fr'], true, false, true,
   ST_SetSRID(ST_MakePoint(4.8322,45.7602),4326)::geography, 4.9, 88, true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO provider_verification (id, provider_id, cabinet_id, identifier, id_type, status, source, checked_at) VALUES
  ('f1000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-0000000000f1','11111111-1111-1111-1111-111111111111','10100000001','rpps','verified','ANS','2026-05-02 10:00+00'),
  ('f1000000-0000-0000-0000-000000000002','f0000000-0000-0000-0000-0000000000f2','11111111-1111-1111-1111-111111111111','10100000002','rpps','verified','ANS','2026-05-02 10:05+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, motif, status) VALUES
  ('a5000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-0000000000f1','2026-06-05 09:00+00','2026-06-05 09:30+00','Consultation','open'),
  ('a5000000-0000-0000-0000-000000000002','f0000000-0000-0000-0000-0000000000f1','2026-06-05 09:30+00','2026-06-05 10:00+00','Consultation','open'),
  ('a5000000-0000-0000-0000-000000000003','f0000000-0000-0000-0000-0000000000f2','2026-06-05 14:00+00','2026-06-05 14:30+00','Détartrage','open')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Comptes patient (plateforme) + proches + couverture santé
-- =====================================================================
INSERT INTO patient_account (id, app_user_id, first_name, last_name, birth_date, contact,
                             regime_obligatoire, tiers_payant, mutuelle) VALUES
  ('e0000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000a5','Marc','Dubois','1979-03-14','{"tel":"+33600000001"}','regime_general', true,
   '{"amc":"MGEN","numero_adherent":"MGEN-001"}'),
  ('e0000000-0000-0000-0000-0000000000e2','a0000000-0000-0000-0000-0000000000a6','Léo','Dubois','2015-09-01','{}','regime_general', true, '{"amc":"MGEN"}'),
  ('e0000000-0000-0000-0000-0000000000e3','a0000000-0000-0000-0000-0000000000a7','Jade','Dubois','2018-11-20','{}','regime_general', true, '{"amc":"MGEN"}'),
  ('e0000000-0000-0000-0000-0000000000e4','a0000000-0000-0000-0000-0000000000a8','Camille','Rousseau','1990-07-22','{"tel":"+33600000004"}','regime_general', false, '{}'),
  ('e0000000-0000-0000-0000-0000000000e5','a0000000-0000-0000-0000-0000000000a9','Karim','Saïdi','1985-01-30','{"tel":"+33600000005"}','ame', true, '{}')
ON CONFLICT (id) DO NOTHING;

-- Marc est titulaire (autorité parentale) de Léo et Jade
INSERT INTO account_guardianship (id, guardian_account_id, dependent_account_id, relationship) VALUES
  ('a9000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-0000000000e1','e0000000-0000-0000-0000-0000000000e2','enfant'),
  ('a9000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-0000000000e1','e0000000-0000-0000-0000-0000000000e3','enfant')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Patients (dossier tenant, lié au compte plateforme)
-- =====================================================================
INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name, birth_date, contact) VALUES
  ('d0000000-0000-0000-0000-0000000000d1','11111111-1111-1111-1111-111111111111','e0000000-0000-0000-0000-0000000000e1','Marc','Dubois','1979-03-14','{"tel":"+33600000001"}'),
  ('d0000000-0000-0000-0000-0000000000d4','11111111-1111-1111-1111-111111111111','e0000000-0000-0000-0000-0000000000e4','Camille','Rousseau','1990-07-22','{"tel":"+33600000004"}'),
  ('d0000000-0000-0000-0000-0000000000d5','11111111-1111-1111-1111-111111111111','e0000000-0000-0000-0000-0000000000e5','Karim','Saïdi','1985-01-30','{"tel":"+33600000005"}')
ON CONFLICT (id) DO NOTHING;

-- Dossiers médicaux (allergies) — PLACEHOLDER chiffré (cf. binaire nubia)
INSERT INTO medical_record (id, cabinet_id, patient_id, data_ciphertext, data_key_ref) VALUES
  ('d6000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1','\x53454544','SEED_PLACEHOLDER'),
  ('d6000000-0000-0000-0000-000000000005','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d5','\x53454544','SEED_PLACEHOLDER')
ON CONFLICT (id) DO NOTHING;

-- Odontogramme de Marc (dent 26 à traiter)
INSERT INTO dental_chart (id, cabinet_id, patient_id, teeth_status) VALUES
  ('d7000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1',
   '{"26":{"status":"a_extraire","plan":"implant"},"36":{"status":"sain"}}')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Passeports implantaires (issue #699)
-- =====================================================================
INSERT INTO implant_passport (id, cabinet_id, patient_id, implant_ref, brand, lot_number, placement_date, tooth_position, notes) VALUES
  ('bb000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1','STR-BL-4.1-10','Straumann','LOT-2024-0012','2026-06-03','26','Pose implant 26 après extraction — cicatrisation en cours'),
  ('bb000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d4','NOB-3.5-12','Nobel Biocare','LOT-2023-0478','2025-11-15','11','Implant antérieur 11 — prothèse posée')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Plan de traitement (3 phases) + devis lié pour Marc
-- =====================================================================
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) VALUES
  ('a1000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1','draft', 2680.00, 'EUR')
ON CONFLICT (id) DO NOTHING;

INSERT INTO treatment_plan (id, cabinet_id, patient_id, practitioner_id, title, status, quote_id) VALUES
  ('a2000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1','c0000000-0000-0000-0000-0000000000c1','Réhabilitation 26 (implant)','in_progress','a1000000-0000-0000-0000-000000000001')
ON CONFLICT (id) DO NOTHING;

INSERT INTO treatment_phase (id, cabinet_id, plan_id, position, title, status) VALUES
  ('a3000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','a2000000-0000-0000-0000-000000000001',1,'Phase 1 · Assainissement','done'),
  ('a3000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','a2000000-0000-0000-0000-000000000001',2,'Phase 2 · Chirurgie implantaire','in_progress'),
  ('a3000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','a2000000-0000-0000-0000-000000000001',3,'Phase 3 · Prothèse','requested')
ON CONFLICT (id) DO NOTHING;

INSERT INTO quote_item (id, cabinet_id, quote_id, phase_id, label, ccam_code, tooth, qty, unit_amount, amo_part, amc_part) VALUES
  ('a4000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','a1000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000001','Détartrage','HBJD001',NULL,1, 60.00, 30.00, 30.00),
  ('a4000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','a1000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000002','Pose implant 26','LBLD017','26',1, 1200.00, 0.00, 400.00),
  ('a4000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','a1000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000003','Couronne implantaire 26','HBLD038','26',1, 1420.00, 107.50, 700.00)
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Wedge : devis sent (Camille 2 060 €), devis signed + acompte payé
-- =====================================================================
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) VALUES
  ('a1000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d4','sent', 2060.00, 'EUR')
ON CONFLICT (id) DO NOTHING;
INSERT INTO quote_item (id, cabinet_id, quote_id, label, ccam_code, tooth, qty, unit_amount, amo_part, amc_part) VALUES
  ('a4000000-0000-0000-0000-000000000010','11111111-1111-1111-1111-111111111111','a1000000-0000-0000-0000-000000000002','Couronne céramique 11','HBLD038','11',1, 2060.00, 107.50, 900.00)
ON CONFLICT (id) DO NOTHING;

INSERT INTO signature (id, cabinet_id, provider, provider_ref, level, signed_at) VALUES
  ('a6000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','yousign','ys_demo_001','aes','2026-05-28 11:00+00')
ON CONFLICT (id) DO NOTHING;
INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, signed_at, signed_sha256, signature_id) VALUES
  ('a1000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d5','signed', 800.00, 'EUR',
   '2026-05-28 11:00+00', repeat('a',64), 'a6000000-0000-0000-0000-000000000001')
ON CONFLICT (id) DO NOTHING;
INSERT INTO payment (id, cabinet_id, patient_id, quote_id, amount, currency, kind, provider, provider_ref, status, idempotency_key) VALUES
  ('a7000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d5','a1000000-0000-0000-0000-000000000003', 240.00,'EUR','deposit','stripe','pi_demo_001','paid','seed-pay-001')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Agenda : journée type (confirmé, au fauteuil, no_show) + file d'attente
-- =====================================================================
INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) VALUES
  ('aa000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1','c0000000-0000-0000-0000-0000000000c1','2026-06-03 09:00+00','2026-06-03 09:45+00','in_progress','Chirurgie implant 26'),
  ('aa000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d4','c0000000-0000-0000-0000-0000000000c2','2026-06-03 10:00+00','2026-06-03 10:30+00','confirmed','Pose couronne'),
  ('aa000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d5','c0000000-0000-0000-0000-0000000000c1','2026-06-03 11:00+00','2026-06-03 11:20+00','no_show','Urgence douleur')
ON CONFLICT (id) DO NOTHING;
INSERT INTO checkin_event (id, cabinet_id, appointment_id, mode, occurred_at) VALUES
  ('ac000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','aa000000-0000-0000-0000-000000000001','qr_app','2026-06-03 08:55+00')
ON CONFLICT (id) DO NOTHING;
INSERT INTO waiting_list_entry (id, cabinet_id, patient_id, desired_window, score, status) VALUES
  ('ad000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d5','{"from":"2026-06-04","to":"2026-06-10"}', 12.5,'active')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Journal clinique (PLACEHOLDER chiffré) + ordonnance signée
-- =====================================================================
INSERT INTO clinical_note (id, cabinet_id, patient_id, author_id, content_ciphertext, content_key_ref, note_kind, tooth, ccam_codes, validated_at) VALUES
  ('ce000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-0000000000a1','\x53454544','SEED_PLACEHOLDER','act','26','["LBLD017"]','2026-06-03 09:40+00'),
  ('ce000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-0000000000a1','\x53454544','SEED_PLACEHOLDER','observation',NULL,'[]','2026-06-03 09:42+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, signed_at) VALUES
  ('cf000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1','c0000000-0000-0000-0000-0000000000c1','signed','2026-06-03 09:45+00')
ON CONFLICT (id) DO NOTHING;
INSERT INTO prescription_item (id, cabinet_id, prescription_id, label, form, posology, duration, quantity) VALUES
  ('cf100000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','cf000000-0000-0000-0000-000000000001','Paracétamol 1 g','comprimé','1 cp x 3 / jour si douleur','5 jours','QSP 15 cp'),
  ('cf100000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','cf000000-0000-0000-0000-000000000001','Amoxicilline 1 g','comprimé','1 cp x 2 / jour','7 jours','QSP 14 cp')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Messagerie : 2 fils urgents + 1 normal (contenu PLACEHOLDER chiffré)
-- =====================================================================
INSERT INTO conversation (id, cabinet_id, patient_id, scope, status) VALUES
  ('c1000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d5','patient_cabinet','open'),
  ('c1000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d1','patient_cabinet','open'),
  ('c1000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','d0000000-0000-0000-0000-0000000000d4','patient_cabinet','open')
ON CONFLICT (id) DO NOTHING;
INSERT INTO message (id, cabinet_id, conversation_id, sender_kind, sender_id, body_ciphertext, body_key_ref, triage_flag, triage_reason, created_at) VALUES
  ('c2000000-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','c1000000-0000-0000-0000-000000000001','patient','d0000000-0000-0000-0000-0000000000d5','\x53454544','SEED_PLACEHOLDER','urgent','mot-clé: douleur','2026-06-03 07:30+00'),
  ('c2000000-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','c1000000-0000-0000-0000-000000000002','patient','d0000000-0000-0000-0000-0000000000d1','\x53454544','SEED_PLACEHOLDER','urgent','mot-clé: saignement','2026-06-03 08:00+00'),
  ('c2000000-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','c1000000-0000-0000-0000-000000000003','patient','d0000000-0000-0000-0000-0000000000d4','\x53454544','SEED_PLACEHOLDER','normal',NULL,'2026-06-02 16:00+00')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Couverture santé patient (issue #1097)
-- Marc Dubois : régime général + mutuelle MGEN fictive
-- =====================================================================
INSERT INTO patient_coverage (id, patient_account_id, regime_obligatoire, amc, numero_adherent, tiers_payant) VALUES
  ('e8000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-0000000000e1','regime_general','MGEN','MGEN-001-FICTIF', true)
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Consentements + 1 avis publié
-- =====================================================================
INSERT INTO consent_record (id, app_user_id, purpose, granted, cgu_version, granted_at) VALUES
  ('cc000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000a5','soins', true, '1.0','2026-05-01 09:00+00')
ON CONFLICT (id) DO NOTHING;

-- Consentement RGPD data_processing pour le compte patient Marc Dubois (issue #1097)
INSERT INTO consent_record (id, patient_account_id, purpose, granted, granted_at) VALUES
  ('cc000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-0000000000e1','data_processing', true,'2026-05-01 09:05+00')
ON CONFLICT (id) DO NOTHING;

INSERT INTO review (id, provider_id, patient_account_id, appointment_id, rating, comment, status, created_at) VALUES
  ('ab000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-0000000000f1','e0000000-0000-0000-0000-0000000000e1','aa000000-0000-0000-0000-000000000001',5,'Praticien à l''écoute, intervention sans douleur.','published','2026-05-15 18:00+00')
ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- Devices FCM push (issue #696) : 1 patient, 1 pro
-- =====================================================================
INSERT INTO device (id, app_user_id, fcm_token, platform) VALUES
  ('ff000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-0000000000a5','fcm_patient_marc_ios','ios'),
  ('ff000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-0000000000a1','fcm_pro_hugo_android','android')
ON CONFLICT (id) DO NOTHING;

COMMIT;

\echo '✓ seed démo chargé (Cabinet Lyon, données fictives, idempotent)'
