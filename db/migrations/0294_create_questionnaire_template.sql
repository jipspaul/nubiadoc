-- 0294_create_questionnaire_template.sql
-- Modèle de questionnaire médical versionné et paramétrable (#7160 DP-F21.a) :
-- medical_questionnaire_submission (migration 0180) a un payload jsonb libre
-- mais aucune table ne décrit le SCHÉMA des questions posées — le
-- questionnaire est actuellement fixe côté applicatif, sans historique de
-- version. Copié sur le modèle de consent_template (migration 0279) /
-- prescription_template (migration 0166) : catalogue global partagé +
-- variantes propres au cabinet, versionnées.
--
-- cabinet_id NULLABLE, même sémantique que consent_template.cabinet_id :
-- NULL = questionnaire standard (catalogue seedé ci-dessous), valeur posée =
-- variante propre au cabinet.
--
-- schema jsonb : liste de questions [{key, type, label, options, condition,
-- safety_flag}]. safety_flag ne fait qu'annoter une question pour un
-- affichage renforcé côté praticien (ex. allergies) — AUCUNE logique
-- décisionnelle automatique (blocage, alerte contre-indication) : hors
-- dispositif médical (MDR), cf. docs/05-modele-de-donnees.md §"Hors
-- dispositif médical" et docs/07-conformite.md §8.
--
-- version/is_active : un cabinet (ou l'équipe produit pour le standard) peut
-- faire évoluer le schéma sans perdre l'historique des soumissions déjà
-- faites sur une version antérieure — on désactive l'ancienne version
-- (is_active = false) plutôt que de la modifier en place.
--
-- medical_questionnaire_submission.template_id/version : chaque soumission
-- référence la version exacte du questionnaire utilisée (utile même si le
-- schéma évolue ensuite). Nullable + backfill des lignes existantes vers le
-- standard v1 seedé ici (elles ont toutes été remplies avec le questionnaire
-- fixe qui précède cette migration).
--
-- RLS à deux policies, identique à consent_template (0279) :
--   - tenant_isolation : un cabinet lit/écrit ses propres modèles
--     (cabinet_id = tenant courant).
--   - global_template_read : SELECT uniquement, cabinet_id IS NULL — le
--     standard (seed) reste visible de tous, jamais modifiable par un
--     cabinet (pas de policy INSERT/UPDATE/DELETE pour cabinet_id NULL :
--     seule une migration peut créer/modifier le standard).

CREATE TABLE questionnaire_template (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id UUID        REFERENCES cabinet(id),
    version    INTEGER     NOT NULL DEFAULT 1,
    title      TEXT        NOT NULL,
    schema     JSONB       NOT NULL,
    is_active  BOOLEAN     NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT questionnaire_template_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT questionnaire_template_version_positive CHECK (version > 0)
);

-- Une seule ligne par (cabinet, version) — et par version pour le standard
-- (cabinet_id NULL n'est pas comparable via une contrainte UNIQUE classique,
-- chaque NULL y est distinct).
CREATE UNIQUE INDEX uq_questionnaire_template_cabinet_version
    ON questionnaire_template (cabinet_id, version) WHERE cabinet_id IS NOT NULL;
CREATE UNIQUE INDEX uq_questionnaire_template_standard_version
    ON questionnaire_template (version) WHERE cabinet_id IS NULL;

CREATE INDEX idx_questionnaire_template_cabinet ON questionnaire_template (cabinet_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON questionnaire_template TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON questionnaire_template TO nubia_seed;

ALTER TABLE questionnaire_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE questionnaire_template FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON questionnaire_template
    FOR ALL
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY global_template_read ON questionnaire_template
    FOR SELECT
    TO nubia_app
    USING (cabinet_id IS NULL);

COMMENT ON TABLE questionnaire_template IS 'Modèle de questionnaire médical versionné. cabinet_id NULL = standard (seedé), sinon propre au cabinet. RLS fail-closed + lecture globale permissive. Issue #7160.';
COMMENT ON COLUMN questionnaire_template.schema IS 'Liste de questions : [{key, type, label, options, condition, safety_flag}]. safety_flag = annotation d''affichage uniquement (pas de logique décisionnelle automatique, hors dispositif médical).';
COMMENT ON COLUMN questionnaire_template.version IS 'Incrémentée à chaque évolution du schéma ; l''ancienne version est désactivée (is_active = false), jamais éditée en place.';

-- ── Seed : questionnaire standard v1 (reprend les champs du questionnaire
-- fixe précédent : allergies, traitements, antécédents...) ────────────────
-- ID déterministe (préfixe 02940000) : idempotent si la migration est
-- rejouée sur une base où le seed existe déjà (ON CONFLICT DO NOTHING).
INSERT INTO questionnaire_template (id, cabinet_id, version, title, schema, is_active) VALUES
  ('02940000-0000-0000-0000-000000000001', NULL, 1, 'Questionnaire médical standard',
   '[
      {"key": "allergies", "type": "text", "label": "Avez-vous des allergies connues (médicaments, latex, métaux...) ?", "options": null, "condition": null, "safety_flag": true},
      {"key": "traitement_en_cours", "type": "text", "label": "Suivez-vous un traitement médical en cours ?", "options": null, "condition": null, "safety_flag": true},
      {"key": "anticoagulants", "type": "boolean", "label": "Prenez-vous un traitement anticoagulant ou antiagrégant ?", "options": null, "condition": null, "safety_flag": true},
      {"key": "grossesse", "type": "boolean", "label": "Êtes-vous enceinte ou envisagez-vous une grossesse ?", "options": null, "condition": null, "safety_flag": true},
      {"key": "maladie_cardiovasculaire", "type": "boolean", "label": "Avez-vous une maladie cardiovasculaire ?", "options": null, "condition": null, "safety_flag": true},
      {"key": "diabete", "type": "boolean", "label": "Êtes-vous diabétique ?", "options": null, "condition": null, "safety_flag": false},
      {"key": "diabete_type", "type": "select", "label": "Si oui, quel type ?", "options": ["Type 1", "Type 2"], "condition": {"key": "diabete", "equals": true}, "safety_flag": false},
      {"key": "tabac", "type": "boolean", "label": "Êtes-vous fumeur ?", "options": null, "condition": null, "safety_flag": false},
      {"key": "antecedents_chirurgicaux", "type": "text", "label": "Avez-vous des antécédents chirurgicaux notables ?", "options": null, "condition": null, "safety_flag": false},
      {"key": "contact_urgence", "type": "text", "label": "Personne à contacter en cas d''urgence (nom et téléphone).", "options": null, "condition": null, "safety_flag": false}
   ]'::jsonb,
   true)
ON CONFLICT (id) DO NOTHING;

-- ── medical_questionnaire_submission référence désormais la version utilisée ──
ALTER TABLE medical_questionnaire_submission
    ADD COLUMN template_id UUID REFERENCES questionnaire_template(id),
    ADD COLUMN version     INTEGER;

UPDATE medical_questionnaire_submission
    SET template_id = '02940000-0000-0000-0000-000000000001',
        version = 1
    WHERE template_id IS NULL;

COMMENT ON COLUMN medical_questionnaire_submission.template_id IS 'Modèle de questionnaire utilisé pour cette soumission (questionnaire_template). Nullable pour compat historique ; backfillé au standard v1 par cette migration. Issue #7160.';
COMMENT ON COLUMN medical_questionnaire_submission.version IS 'Version du modèle utilisée au moment de la soumission (dénormalisée depuis questionnaire_template.version). Issue #7160.';
