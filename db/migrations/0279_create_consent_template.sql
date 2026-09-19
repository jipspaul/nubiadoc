-- 0279_create_consent_template.sql
-- Bibliothèque de consentements éclairés (#7200 DP-F6.a) : consent_record
-- (migration 0008) trace qu'un consentement a été donné, mais aucune table
-- ne fournit le texte type à faire signer par acte. Copié sur le modèle de
-- prescription_template (migration 0166) : catalogue global partagé +
-- variantes propres au cabinet.
--
-- cabinet_id NULLABLE, même sémantique que prescription_template.cabinet_id :
-- NULL = modèle global (catalogue standard seedé ci-dessous), valeur posée =
-- variante propre au cabinet.
--
-- version/is_active : un cabinet peut faire évoluer le texte d'un modèle
-- (relecture juridique, changement de protocole) sans perdre l'historique
-- des versions déjà signées via consent_record — on désactive l'ancienne
-- version (is_active = false) plutôt que de la modifier en place.
--
-- RLS à deux policies, identique à prescription_template (0166) :
--   - tenant_isolation : un cabinet lit/écrit ses propres modèles
--     (cabinet_id = tenant courant).
--   - global_template_read : SELECT uniquement, cabinet_id IS NULL — le
--     catalogue global (seed) reste visible de tous, jamais modifiable par
--     un cabinet (pas de policy INSERT/UPDATE/DELETE pour cabinet_id NULL :
--     seule une migration peut créer/modifier un modèle global).

CREATE TABLE consent_template (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id    UUID        REFERENCES cabinet(id),
    act_category  TEXT        NOT NULL,
    title         TEXT        NOT NULL,
    body_markdown TEXT        NOT NULL,
    version       INTEGER     NOT NULL DEFAULT 1,
    is_active     BOOLEAN     NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT consent_template_title_not_blank CHECK (btrim(title) <> ''),
    CONSTRAINT consent_template_body_not_blank CHECK (btrim(body_markdown) <> ''),
    CONSTRAINT consent_template_version_positive CHECK (version > 0),
    CONSTRAINT consent_template_act_category_check CHECK (act_category IN (
        'chirurgie_orale',
        'parodontologie',
        'implantologie',
        'prothese_amovible_partielle',
        'prothese_amovible_totale',
        'prothese_fixe_unitaire',
        'prothese_fixe_plurale',
        'orthodontie',
        'pedodontie',
        'endodontie'
    ))
);

CREATE INDEX idx_consent_template_cabinet ON consent_template (cabinet_id);
CREATE INDEX idx_consent_template_act_category ON consent_template (act_category);

GRANT SELECT, INSERT, UPDATE, DELETE ON consent_template TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON consent_template TO nubia_seed;

ALTER TABLE consent_template ENABLE ROW LEVEL SECURITY;
ALTER TABLE consent_template FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON consent_template
    FOR ALL
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

CREATE POLICY global_template_read ON consent_template
    FOR SELECT
    TO nubia_app
    USING (cabinet_id IS NULL);

COMMENT ON TABLE consent_template IS 'Modèles de consentement éclairé réutilisables par type d''acte. cabinet_id NULL = modèle global (seedé), sinon propre au cabinet. RLS fail-closed + lecture globale permissive. Issue #7200.';
COMMENT ON COLUMN consent_template.act_category IS 'Type d''acte couvert par le modèle (chirurgie_orale couvre aussi les avulsions/extractions).';
COMMENT ON COLUMN consent_template.body_markdown IS 'Texte du consentement en Markdown, à faire relire/valider par le praticien avant usage — point de départ, pas un texte médico-légal validé.';
COMMENT ON COLUMN consent_template.version IS 'Incrémentée à chaque évolution du texte ; l''ancienne version est désactivée (is_active = false), jamais éditée en place.';

-- ── Seed : catalogue standard (10 types d'acte) ─────────────────────────────
-- -- seed v1 : texte générique, non médical-décisionnel, à faire relire par
-- un praticien/juriste avant usage réel — cf. consent_record qui trace la
-- signature mais ne garantit en rien la validité du contenu présenté.
-- IDs déterministes (préfixe 02790000) : idempotent si la migration est
-- rejouée sur une base où le seed existe déjà (ON CONFLICT DO NOTHING).
INSERT INTO consent_template (id, cabinet_id, act_category, title, body_markdown, version) VALUES
  ('02790000-0000-0000-0000-000000000001', NULL, 'chirurgie_orale',
   'Consentement — Chirurgie orale (avulsion / geste chirurgical)',
   E'# Consentement éclairé — Chirurgie orale\n\nJe soussigné(e) reconnais avoir été informé(e) par mon praticien de la nature de l''intervention de chirurgie orale envisagée (y compris avulsion dentaire), de ses bénéfices attendus, des alternatives possibles et des risques et suites habituelles (douleur, œdème, saignement, infection). J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise mon praticien à réaliser cet acte.',
   1),
  ('02790000-0000-0000-0000-000000000002', NULL, 'parodontologie',
   'Consentement — Traitement parodontal',
   E'# Consentement éclairé — Parodontologie\n\nJe soussigné(e) reconnais avoir été informé(e) de la nature du traitement parodontal envisagé, de ses objectifs, des alternatives et des suites possibles (sensibilité, récession gingivale). J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise mon praticien à réaliser ce traitement.',
   1),
  ('02790000-0000-0000-0000-000000000003', NULL, 'implantologie',
   'Consentement — Pose d''implant(s) dentaire(s)',
   E'# Consentement éclairé — Implantologie\n\nJe soussigné(e) reconnais avoir été informé(e) de la nature de la pose d''implant(s) envisagée, des examens préalables réalisés, des alternatives (prothèse conventionnelle) et des risques et suites possibles (échec d''ostéointégration, complications sinusiennes ou nerveuses). J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise mon praticien à réaliser cet acte.',
   1),
  ('02790000-0000-0000-0000-000000000004', NULL, 'prothese_amovible_partielle',
   'Consentement — Prothèse amovible partielle',
   E'# Consentement éclairé — Prothèse amovible partielle\n\nJe soussigné(e) reconnais avoir été informé(e) des caractéristiques de la prothèse amovible partielle envisagée, de ses limites (délai d''adaptation, entretien) et des alternatives possibles. J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise mon praticien à réaliser cet acte.',
   1),
  ('02790000-0000-0000-0000-000000000005', NULL, 'prothese_amovible_totale',
   'Consentement — Prothèse amovible totale',
   E'# Consentement éclairé — Prothèse amovible totale\n\nJe soussigné(e) reconnais avoir été informé(e) des caractéristiques de la prothèse amovible totale envisagée, de ses limites (délai d''adaptation, entretien, stabilité) et des alternatives possibles (implants). J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise mon praticien à réaliser cet acte.',
   1),
  ('02790000-0000-0000-0000-000000000006', NULL, 'prothese_fixe_unitaire',
   'Consentement — Prothèse fixe unitaire (couronne)',
   E'# Consentement éclairé — Prothèse fixe unitaire\n\nJe soussigné(e) reconnais avoir été informé(e) de la nature de la couronne/prothèse fixe unitaire envisagée, de la préparation dentaire nécessaire, des alternatives et des risques (sensibilité, dévitalisation ultérieure éventuelle). J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise mon praticien à réaliser cet acte.',
   1),
  ('02790000-0000-0000-0000-000000000007', NULL, 'prothese_fixe_plurale',
   'Consentement — Prothèse fixe plurale (bridge)',
   E'# Consentement éclairé — Prothèse fixe plurale\n\nJe soussigné(e) reconnais avoir été informé(e) de la nature du bridge/prothèse fixe plurale envisagé, de la préparation des dents piliers, des alternatives (implants) et des risques et suites possibles. J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise mon praticien à réaliser cet acte.',
   1),
  ('02790000-0000-0000-0000-000000000008', NULL, 'orthodontie',
   'Consentement — Traitement orthodontique',
   E'# Consentement éclairé — Orthodontie\n\nJe soussigné(e) (ou représentant légal) reconnais avoir été informé(e) de la nature et de la durée estimée du traitement orthodontique envisagé, des contraintes de port et d''hygiène, et des alternatives possibles. J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise mon praticien à réaliser ce traitement.',
   1),
  ('02790000-0000-0000-0000-000000000009', NULL, 'pedodontie',
   'Consentement — Soin pédodontique (représentant légal)',
   E'# Consentement éclairé — Pédodontie\n\nJe soussigné(e), représentant légal de l''enfant, reconnais avoir été informé(e) de la nature du soin envisagé, des alternatives et des modalités de prise en charge adaptées à l''enfant. J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise le praticien à réaliser ce soin sur l''enfant dont j''ai la responsabilité légale.',
   1),
  ('02790000-0000-0000-0000-000000000010', NULL, 'endodontie',
   'Consentement — Traitement endodontique (dévitalisation)',
   E'# Consentement éclairé — Endodontie\n\nJe soussigné(e) reconnais avoir été informé(e) de la nature du traitement endodontique (dévitalisation) envisagé, des alternatives (extraction) et des risques et suites possibles (échec du traitement, fragilisation de la dent). J''ai pu poser mes questions et j''ai disposé d''un délai de réflexion suffisant. J''autorise mon praticien à réaliser cet acte.',
   1)
ON CONFLICT (id) DO NOTHING;
