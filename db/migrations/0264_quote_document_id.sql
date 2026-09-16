-- 0264_quote_document_id.sql
-- #7046 : « Télécharger le devis signé » n'apparaît sur aucun devis signé —
-- le front (quote_detail_view.dart) conditionne le CTA à `quote.documentId`,
-- mais `quote` n'a jamais porté de colonne `document_id` et aucun PDF n'était
-- généré à la signature (`billing::sign_quote`, stub Yousign historique).
--
-- FK simple sur `document(id)` (contrairement à `practitioner_id` ci-dessus,
-- migration 0258 : pas de risque de référencer un document d'un autre
-- cabinet, `sign_quote` insère lui-même la ligne `document` juste avant de
-- poser cette colonne, dans la même transaction).

ALTER TABLE quote
    ADD COLUMN document_id uuid REFERENCES document (id);
