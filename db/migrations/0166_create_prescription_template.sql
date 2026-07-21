-- 0166_create_prescription_template.sql
-- Modèles d'ordonnance réutilisables (#4073) : le praticien retape chaque
-- ordonnance de zéro, aucune table ne permet d'enregistrer un modèle
-- réutilisable (par praticien) ni un catalogue standard (antibioprophylaxie,
-- antalgiques post-op). Sur le modèle de prescription/prescription_item
-- (migration 0010) pour la forme des lignes (items jsonb).
--
-- cabinet_id NULLABLE (contrairement à prescription/prescription_item,
-- toujours NOT NULL) : un modèle global (seedé ci-dessous, ex. protocole
-- ANSM/HAS standard) doit être lisible par TOUT cabinet, pas un seul —
-- NULL = modèle global, valeur posée = modèle propre au cabinet.
-- practitioner_id NULLABLE : NULL = modèle partagé par tout le cabinet,
-- valeur posée = modèle personnel d'un praticien.
--
-- RLS à deux policies (permissif, même pattern que les policies
-- *_patient_read de la migration 0029, "OR avec tenant_isolation cabinet") :
--   - tenant_isolation : un cabinet lit/écrit ses propres modèles
--     (cabinet_id = tenant courant).
--   - global_template_read : SELECT uniquement, cabinet_id IS NULL — les
--     modèles globaux (seed) restent visibles de tous, jamais modifiables
--     par un cabinet (pas de policy INSERT/UPDATE/DELETE pour cabinet_id
--     NULL : seule une migration peut créer/modifier un modèle global).

CREATE TABLE prescription_template (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id      UUID        REFERENCES cabinet(id),
    practitioner_id UUID        REFERENCES practitioner(id),
    label           TEXT        NOT NULL,
    items           JSONB       NOT NULL DEFAULT '[]',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT prescription_template_label_not_blank CHECK (btrim(label) <> '')
);

CREATE INDEX idx_prescription_template_cabinet
    ON prescription_template (cabinet_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON prescription_template TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON prescription_template TO nubia_seed;

ALTER TABLE prescription_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE prescription_template FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON prescription_template
    FOR ALL
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY global_template_read ON prescription_template
    FOR SELECT
    TO nubia_app
    USING (cabinet_id IS NULL);

COMMENT ON TABLE prescription_template IS 'Modèles d''ordonnance réutilisables. cabinet_id NULL = modèle global (seedé), sinon propre au cabinet. RLS fail-closed + lecture globale permissive. Issue #4073.';
COMMENT ON COLUMN prescription_template.items IS 'Lignes du modèle, même forme que prescription_item : [{label, form, posology, duration, quantity}].';

-- ── Seed : modèles dentaires standards (protocoles ANSM/HAS courants) ───────
-- Comme tout modèle, à valider/adapter par le praticien avant signature —
-- prescriptions.rs rappelle déjà qu'aucun contrôle automatique d'allergie/
-- interaction n'existe et que le praticien décide seul (#07 §8.6). Ces
-- modèles sont un point de départ, pas une prescription pré-validée.
-- IDs déterministes (préfixe 01660000) : idempotent si la migration est
-- rejouée sur une base où le seed existe déjà (ON CONFLICT DO NOTHING).
INSERT INTO prescription_template (id, cabinet_id, practitioner_id, label, items) VALUES
  ('01660000-0000-0000-0000-000000000001', NULL, NULL,
   'Antibioprophylaxie amoxicilline (avulsion à risque)',
   '[{"label": "Amoxicilline 2 g", "form": "comprimé", "posology": "Prise unique 1h avant le geste", "duration": "1 jour", "quantity": "2 g"}]'::jsonb),
  ('01660000-0000-0000-0000-000000000002', NULL, NULL,
   'Antibioprophylaxie clindamycine (allergie pénicilline)',
   '[{"label": "Clindamycine 600 mg", "form": "comprimé", "posology": "Prise unique 1h avant le geste", "duration": "1 jour", "quantity": "600 mg"}]'::jsonb),
  ('01660000-0000-0000-0000-000000000003', NULL, NULL,
   'Antalgique post-opératoire palier 1',
   '[{"label": "Paracétamol 1 g", "form": "comprimé", "posology": "1 cp x 3/jour si douleur", "duration": "5 jours", "quantity": "QSP 15 cp"}]'::jsonb),
  ('01660000-0000-0000-0000-000000000004', NULL, NULL,
   'Antalgique post-opératoire palier 2 (AINS)',
   '[{"label": "Ibuprofène 400 mg", "form": "comprimé", "posology": "1 cp x 3/jour au cours des repas si douleur", "duration": "3 à 5 jours", "quantity": "QSP 15 cp"}]'::jsonb),
  ('01660000-0000-0000-0000-000000000005', NULL, NULL,
   'Bain de bouche post-extraction',
   '[{"label": "Chlorhexidine 0,12 %", "form": "solution pour bain de bouche", "posology": "2 bains de bouche par jour, ne pas avaler", "duration": "7 jours", "quantity": "1 flacon"}]'::jsonb)
ON CONFLICT (id) DO NOTHING;
