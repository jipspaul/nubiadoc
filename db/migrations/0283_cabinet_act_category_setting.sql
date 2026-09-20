-- 0283_cabinet_act_category_setting.sql
-- [DP-F11.a] Catégories d'actes activées par cabinet (#7187) : permet de
-- masquer côté UI les catégories d'actes non pratiquées par un cabinet
-- (ex. mode « full ortho » qui masque chirurgie/implanto/esthétique...).
--
-- 1. `ccam_act.category` — colonne absente du catalogue (0119/0225) : ajoutée
--    ici puis backfillée. Le catalogue actuel (0119 + extension 0225) est un
--    extrait représentatif, pas la nomenclature CCAM complète par plage de
--    codes : le backfill documente donc explicitement, par groupe de codes,
--    la catégorie de chaque acte existant (une seule catégorie par acte).
--    `ortho` et `atm` n'ont aucun acte dans le catalogue actuel — catégories
--    réservées pour de futurs ajouts, déjà disponibles au réglage cabinet.
-- 2. `cabinet_act_category_setting` — une ligne = un override explicite d'un
--    cabinet pour une catégorie (activée/désactivée). Absence de ligne =
--    catégorie active par défaut (l'API applique ce défaut applicatif).

-- ─── 1. Colonne category sur le catalogue CCAM ──────────────────────────────

ALTER TABLE ccam_act ADD COLUMN category text;

-- Consultation / dépistage.
UPDATE ccam_act SET category = 'consultation'
  WHERE code IN ('HBQK002', 'HBPD001', 'HBQP002');

-- Soins conservateurs (obturations, prévention, anesthésie/sédation).
UPDATE ccam_act SET category = 'soins_conservateurs'
  WHERE code IN ('HBJD001', 'HBJD002', 'HBJD003', 'HBFD003', 'HBFD004',
                  'HBGD432', 'YYYY015', 'YYYY030');

-- Endodontie.
UPDATE ccam_act SET category = 'endo'
  WHERE code IN ('HBED001', 'HBED002', 'HBED003', 'HBED013', 'HBED029',
                  'HBED042', 'HBLD012');

-- Parodontologie.
UPDATE ccam_act SET category = 'paro'
  WHERE code IN ('HBGD036', 'HBGD017', 'HBFD001', 'HBFD002', 'HBLD745',
                  'HBGD473', 'HBGD007', 'HBQK001', 'HBGA045');

-- Prothèse fixe (inlay-core, couronne, bridge, réparation/dépose).
UPDATE ccam_act SET category = 'prothese'
  WHERE code IN ('HBBD001', 'HBLD036', 'HBMD490', 'HBLD038', 'HBLD467',
                  'HBMD002', 'HBLD027', 'HBLD055', 'HBMD481', 'HBMD500',
                  'HBMD030');

-- Appareillages (prothèse amovible).
UPDATE ccam_act SET category = 'appareillages'
  WHERE code IN ('HBLD449', 'HBLD450', 'HBLD451', 'HBLD452');

-- Chirurgie orale.
UPDATE ccam_act SET category = 'chirurgie'
  WHERE code IN ('HBLD724', 'HBGD047', 'TRAUMA1', 'HBFD027', 'HBFA015',
                  'HBLD005', 'HBLD030', 'HBGA027', 'HBBD010', 'HBFD010');

-- Implantologie.
UPDATE ccam_act SET category = 'implanto'
  WHERE code IN ('HBLD001', 'HBMD001', 'HBBD002', 'HBLD060');

-- Imagerie.
UPDATE ccam_act SET category = 'imagerie'
  WHERE code IN ('HBQD001', 'HBQD003', 'LBQK001', 'HBQD012', 'HBQD028');

-- Esthétique.
UPDATE ccam_act SET category = 'esthetique'
  WHERE code IN ('HBHD001');

ALTER TABLE ccam_act ALTER COLUMN category SET NOT NULL;
ALTER TABLE ccam_act ADD CONSTRAINT ccam_act_category_check CHECK (category IN (
                'consultation', 'soins_conservateurs', 'endo', 'paro',
                'prothese', 'ortho', 'chirurgie', 'implanto', 'imagerie',
                'atm', 'esthetique', 'appareillages'));

COMMENT ON COLUMN ccam_act.category IS
    'Catégorie d''acte (mode « full ortho », #7187) : pilote cabinet_act_category_setting.';

-- ─── 2. Réglage cabinet : catégories activées/désactivées ─────────────────

CREATE TABLE cabinet_act_category_setting (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    cabinet_id  uuid        NOT NULL REFERENCES cabinet(id),
    category    text        NOT NULL CHECK (category IN (
                'consultation', 'soins_conservateurs', 'endo', 'paro',
                'prothese', 'ortho', 'chirurgie', 'implanto', 'imagerie',
                'atm', 'esthetique', 'appareillages')),
    enabled     boolean     NOT NULL DEFAULT true,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT cabinet_act_category_setting_unique UNIQUE (cabinet_id, category)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_act_category_setting TO nubia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON cabinet_act_category_setting TO nubia_seed;

-- RLS : isolation par cabinet (fail-closed : GUC absent → 0 ligne).
ALTER TABLE cabinet_act_category_setting ENABLE ROW LEVEL SECURITY;
ALTER TABLE cabinet_act_category_setting FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON cabinet_act_category_setting
    FOR ALL
    TO nubia_app
    USING      (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid)
    WITH CHECK (cabinet_id = nullif(current_setting('app.current_cabinet_id', true), '')::uuid);

COMMENT ON TABLE cabinet_act_category_setting IS
    'Override cabinet d''activation/désactivation d''une catégorie d''actes (mode « full ortho »). Absence de ligne = catégorie active par défaut. Table tenant (cabinet_id). RLS fail-closed. #7187.';
