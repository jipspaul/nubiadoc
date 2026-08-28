-- 0238_prescription_item_design_v2_fields.sql
-- jips/nubiadoc#6101 : les 6 issues design-v2 (#4991-#4999) ont ajouté à
-- PrescriptionItem/PrescriptionItemDto les champs structured_posology,
-- product_reference, non_substitution_reason et non_renouvelable, envoyés
-- par le front (PrescriptionItemDto.toJson()) — mais prescription_item n'a
-- aucune colonne pour les recevoir : perte de données silencieuse dès la
-- création (POST 201 mais champs jamais persistés). "non substituable" et
-- "non renouvelable" sont des mentions légales qui engagent le pharmacien
-- lors de la délivrance, d'où leur gravité.

ALTER TABLE prescription_item
    ADD COLUMN structured_posology jsonb,
    ADD COLUMN product_reference jsonb,
    ADD COLUMN non_substitution_reason text,
    ADD COLUMN non_renouvelable boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN prescription_item.structured_posology IS
    'Posologie décomposée {dose, frequency_per_day, duration_in_days} (design-v2, #4991-#4999). NULL pour les lignes en texte libre.';
COMMENT ON COLUMN prescription_item.product_reference IS
    'Référence produit référentiel médicament {id, dci, galenic_form, therapeutic_class} (design-v2, #4991-#4999). NULL hors référentiel.';
COMMENT ON COLUMN prescription_item.non_substitution_reason IS
    'Motif de la mention légale "non substituable" (ex. MTE — marge thérapeutique étroite). NULL si substituable.';
COMMENT ON COLUMN prescription_item.non_renouvelable IS
    'Mention légale "non renouvelable" choisie par le praticien.';
