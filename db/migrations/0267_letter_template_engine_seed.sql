-- 0267_letter_template_engine_seed.sql
-- Moteur de courriers types (#7197, parité Dental Pilot F7.a) : la table
-- `letter_template` (migration 0167) n'avait que le schéma. Cette migration
-- prépare ce qu'il faut au moteur de substitution + rendu PDF de
-- `api/src/letters.rs` :
--
-- 1. `cabinet_id` devient NULLABLE : NULL = courrier type global (seedé
--    ci-dessous, lisible par tout cabinet), valeur posée = courrier propre
--    au cabinet — même modèle que `prescription_template` (migration 0166).
--    Policy `global_template_read` en SELECT seul : un cabinet ne peut ni
--    modifier ni supprimer un modèle global (seule une migration le peut).
-- 2. `kind` accepte `attestation` (attestation de présence, demandée par
--    l'issue) en plus des valeurs de 0167.
-- 3. `document.category` accepte `courrier` : le PDF rendu est stocké
--    comme document patient (mécanisme `document` existant, pas de nouveau
--    stockage) ; aucune catégorie existante ne convenait (`cr`/`consigne`
--    sont cliniques, `attestation` trop étroit). Catégorie administrative :
--    visible du secrétariat comme `devis`/`facture` (cf.
--    `clinical::NON_CLINICAL_CATEGORIES`).
-- 4. Seed de 4 courriers types globaux, en français, texte sobre. Les
--    placeholders sont ceux du moteur (`letters::KNOWN_PLACEHOLDERS`) :
--    patient.prenom, patient.nom, patient.date_naissance, cabinet.nom,
--    cabinet.adresse, cabinet.telephone, praticien.nom, praticien.rpps,
--    rdv.date, rdv.heure, date.aujourdhui, correspondant.nom.
--    IDs déterministes (préfixe 02670000), ON CONFLICT DO NOTHING.

-- ── 1. Modèles globaux ────────────────────────────────────────────────────

ALTER TABLE letter_template ALTER COLUMN cabinet_id DROP NOT NULL;

CREATE POLICY global_template_read ON letter_template
    FOR SELECT
    TO nubia_app
    USING (cabinet_id IS NULL);

COMMENT ON COLUMN letter_template.cabinet_id IS 'NULL = courrier type global (seedé par migration, lecture seule pour les cabinets), sinon propre au cabinet. Issue #7197.';

-- ── 2. kind : + attestation ───────────────────────────────────────────────

ALTER TABLE letter_template DROP CONSTRAINT letter_template_kind_check;
ALTER TABLE letter_template ADD CONSTRAINT letter_template_kind_check
    CHECK (kind IN ('convocation', 'relance', 'courrier_confrere', 'attestation', 'autre'));

-- ── 3. document.category : + courrier ─────────────────────────────────────

ALTER TABLE document DROP CONSTRAINT document_category_check;
ALTER TABLE document ADD CONSTRAINT document_category_check
    CHECK (category IN (
        'devis', 'facture', 'ordonnance', 'radio', 'cbct', 'photo', 'cr',
        'consigne', 'attestation', 'carte_mutuelle', 'passeport_implantaire',
        'consentement', 'courrier'
    ));

-- ── 4. Seed : 4 courriers types globaux ───────────────────────────────────

INSERT INTO letter_template (id, cabinet_id, name, kind, body_template) VALUES
  ('02670000-0000-0000-0000-000000000001', NULL,
   'Convocation à un rendez-vous', 'convocation',
   E'Madame, Monsieur {{patient.prenom}} {{patient.nom}},\n\nNous vous confirmons votre rendez-vous au cabinet {{cabinet.nom}} le {{rdv.date}} à {{rdv.heure}}, avec le Dr {{praticien.nom}}.\n\nEn cas d''empêchement, merci de nous prévenir au plus tôt au {{cabinet.telephone}}.\n\nNous vous prions d''agréer, Madame, Monsieur, l''expression de nos salutations distinguées.\n\nLe secrétariat'),
  ('02670000-0000-0000-0000-000000000002', NULL,
   'Relance patient sans nouvelles', 'relance',
   E'Madame, Monsieur {{patient.prenom}} {{patient.nom}},\n\nSauf erreur de notre part, nous restons sans nouvelles de vous concernant la suite de vos soins au cabinet {{cabinet.nom}}.\n\nNous vous invitons à nous contacter au {{cabinet.telephone}} afin de convenir d''un rendez-vous.\n\nNous vous prions d''agréer, Madame, Monsieur, l''expression de nos salutations distinguées.\n\nLe secrétariat'),
  ('02670000-0000-0000-0000-000000000003', NULL,
   'Courrier à un confrère', 'courrier_confrere',
   E'Cher confrère, chère consœur {{correspondant.nom}},\n\nJe me permets de vous adresser {{patient.prenom}} {{patient.nom}}, né(e) le {{patient.date_naissance}}, que je suis au cabinet {{cabinet.nom}}.\n\nJe vous remercie par avance de bien vouloir le/la recevoir et reste à votre disposition pour tout complément d''information.\n\nBien confraternellement,\n\nDr {{praticien.nom}}\nRPPS {{praticien.rpps}}'),
  ('02670000-0000-0000-0000-000000000004', NULL,
   'Attestation de présence', 'attestation',
   E'Je soussigné(e), Dr {{praticien.nom}} (RPPS {{praticien.rpps}}), atteste que {{patient.prenom}} {{patient.nom}}, né(e) le {{patient.date_naissance}}, s''est présenté(e) au cabinet {{cabinet.nom}} le {{rdv.date}} à {{rdv.heure}}.\n\nAttestation établie à la demande de l''intéressé(e) pour faire valoir ce que de droit.\n\nFait le {{date.aujourdhui}}.\n\nDr {{praticien.nom}}')
ON CONFLICT (id) DO NOTHING;
