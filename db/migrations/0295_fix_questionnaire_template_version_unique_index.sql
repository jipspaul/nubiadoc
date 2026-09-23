-- 0295_fix_questionnaire_template_version_unique_index.sql
-- Fix #7506 : après un DELETE (is_active = false) puis un nouveau POST, la
-- ligne v1 désactivée occupe toujours (cabinet_id, version=1) — le nouvel
-- INSERT (qui repart à version=1 par défaut, cf. api/src/
-- questionnaire_templates.rs::create_questionnaire_template) percute
-- uq_questionnaire_template_cabinet_version (migration 0294) et échoue en
-- violation de contrainte unique → 500 internal_error, à vie (aucune version
-- désactivée n'est réanimable). L'index portait sur TOUTES les lignes,
-- actives ou non, alors que la garde métier `QuestionnaireTemplateAlreadyExists`
-- (POST) et la doctrine de versionnage (doc de module :10-17) ne visent qu'à
-- garantir UNE SEULE ligne ACTIVE par (cabinet, version) — les versions
-- désactivées d'un cycle précédent ne doivent pas bloquer un nouveau cycle
-- créer/supprimer. On recrée l'index en le scopant à is_active = true.
DROP INDEX uq_questionnaire_template_cabinet_version;

CREATE UNIQUE INDEX uq_questionnaire_template_cabinet_version
    ON questionnaire_template (cabinet_id, version)
    WHERE cabinet_id IS NOT NULL AND is_active = true;
