-- 112_questionnaire_template_recreate_after_delete.sql
-- pgTAP : régression #7506 — après désactivation (DELETE applicatif,
-- is_active = false) du modèle cabinet, un cabinet doit pouvoir recréer un
-- modèle propre (nouveau POST, qui repart à version = 1 par défaut,
-- cf. api/src/questionnaire_templates.rs::create_questionnaire_template).
-- uq_questionnaire_template_cabinet_version (migration 0294) portait sur
-- TOUTES les lignes (actives ou non) et bloquait ce cycle en
-- unique_violation (23505) — fixé en 0295 en scopant l'index aux lignes
-- actives (WHERE cabinet_id IS NOT NULL AND is_active = true).
-- Exécuté par pg_prove sous nubia_app (NOSUPERUSER, NOBYPASSRLS).
-- Fixtures auto-contenues (BEGIN…ROLLBACK). Préfixe UUID 75060000.
-- Issue : #7506

BEGIN;
SELECT plan(2);

SET LOCAL app.current_cabinet_id = '75060000-0000-0000-0000-000000000001';
INSERT INTO cabinet (id, raison_sociale) VALUES
  ('75060000-0000-0000-0000-000000000001', 'Cabinet QuestionnaireTemplate-7506');

-- Cycle 1 : création puis désactivation (comme DELETE), version = 1 (défaut).
INSERT INTO questionnaire_template (id, cabinet_id, title, schema) VALUES
  ('75060000-0000-0000-0000-000000000010',
   '75060000-0000-0000-0000-000000000001',
   'Modèle cabinet 7506 v1',
   '[{"key": "test", "type": "text", "label": "Question test", "options": null, "condition": null, "safety_flag": false}]'::jsonb);

UPDATE questionnaire_template SET is_active = false
  WHERE id = '75060000-0000-0000-0000-000000000010';

-- Cycle 2 : recréation — repart également à version = 1 (défaut), l'ancienne
-- ligne désactivée occupe déjà (cabinet_id, version=1) mais n'est plus
-- active : ne doit PLUS lever d'unique_violation (23505).
SELECT lives_ok(
  $$ INSERT INTO questionnaire_template (id, cabinet_id, title, schema) VALUES
       ('75060000-0000-0000-0000-000000000011',
        '75060000-0000-0000-0000-000000000001',
        'Modèle cabinet 7506 v2 (recréé)',
        '[{"key": "test2", "type": "text", "label": "Autre question", "options": null, "condition": null, "safety_flag": false}]'::jsonb) $$,
  '#7506 : recréer un modèle cabinet après désactivation ne percute plus uq_questionnaire_template_cabinet_version');

SELECT is(
  (SELECT count(*)::int FROM questionnaire_template
   WHERE cabinet_id = '75060000-0000-0000-0000-000000000001' AND is_active = true),
  1,
  '#7506 : exactement un modèle actif pour le cabinet après le cycle créer/supprimer/recréer');

SELECT * FROM finish();
ROLLBACK;
