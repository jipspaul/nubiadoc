-- 0271_cabinet_seed_fix_missing_phone.sql
-- #7269 (re-vérification de #7242, commit 2023dc38) : le téléphone
-- `{{cabinet.telephone}}` ajouté par #7242 n'a été écrit que dans
-- `db/seed/seed.sql`, via un `INSERT ... ON CONFLICT (id) DO NOTHING`. Sur
-- tout environnement où la ligne `cabinet 11111111-…` existait déjà, ce
-- `DO NOTHING` ignore purement la nouvelle valeur et le champ n'est jamais
-- écrit — contrairement à la correction du même correctif pour
-- `letter_template` (migration 0270), qui utilise un vrai `UPDATE`. Les
-- modèles globaux « Convocation à un rendez-vous » et « Relance patient
-- sans nouvelles » (0267) restent donc INGÉNÉRABLES
-- (`missing_placeholder_values: ["cabinet.telephone"]`).
-- Migration immuable (règle `db/migrations/README.md`) : correction du
-- cabinet seedé via UPDATE, même remède que 0270.

UPDATE cabinet
SET settings = jsonb_set(settings, '{contact,phone}', '"+33478000000"', true)
WHERE id = '11111111-1111-1111-1111-111111111111'
  AND settings->'contact'->>'phone' IS NULL;
