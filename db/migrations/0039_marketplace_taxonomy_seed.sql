-- 0039_marketplace_taxonomy_seed.sql
-- Référentiels marketplace : données initiales de profession, specialty, medical_act.
-- Issue #530. Tables créées en 0009 ; ce fichier insère le catalogue de base
-- (lookup data < 100 lignes — cf. postgres-sqlx-migrations §6).
-- Lecture publique : pas de RLS, pas de policy (docs/07 §4.7).

INSERT INTO profession (id, label) VALUES
  ('d1000000-0000-0000-0000-000000000001', 'Chirurgien-dentiste'),
  ('d1000000-0000-0000-0000-000000000002', 'Orthodontiste')
ON CONFLICT (id) DO NOTHING;

INSERT INTO specialty (id, profession_id, label) VALUES
  ('d2000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'Omnipratique'),
  ('d2000000-0000-0000-0000-000000000002', 'd1000000-0000-0000-0000-000000000001', 'Implantologie'),
  ('d2000000-0000-0000-0000-000000000003', 'd1000000-0000-0000-0000-000000000002', 'Orthodontie')
ON CONFLICT (id) DO NOTHING;

INSERT INTO medical_act (id, specialty_id, label, motifs) VALUES
  ('d3000000-0000-0000-0000-000000000001', 'd2000000-0000-0000-0000-000000000001', 'Détartrage',                ARRAY['controle', 'hygiene', 'HBJD001']),
  ('d3000000-0000-0000-0000-000000000002', 'd2000000-0000-0000-0000-000000000002', 'Pose d''implant',            ARRAY['implant', 'dent manquante', 'LBLD017']),
  ('d3000000-0000-0000-0000-000000000003', 'd2000000-0000-0000-0000-000000000001', 'Couronne céramo-métallique', ARRAY['couronne', 'prothese', 'HBLD038']),
  ('d3000000-0000-0000-0000-000000000004', 'd2000000-0000-0000-0000-000000000003', 'Bilan orthodontique',        ARRAY['bague', 'malocclusion', 'OBSD001']),
  ('d3000000-0000-0000-0000-000000000005', 'd2000000-0000-0000-0000-000000000003', 'Contention orthodontique',   ARRAY['contention', 'stabilisation', 'OBSD009'])
ON CONFLICT (id) DO NOTHING;
