-- 0213_quote_signature_composite_fk.sql
-- #4291 : groupes "quote" (4 enfants) et "signature" (2 enfants) de
-- l'audit systémique — FK simples entre tables tenant-scopées converties
-- en composite (id, cabinet_id), même pattern que tous les fix précédents
-- de cette série (0190, 0198, 0200, 0210, 0211, 0212).
--
-- quote : quote_item.quote_id, payment_schedule.quote_id, payment.quote_id,
-- treatment_plan.quote_id. `payment.pharmacy_quote_id -> pharmacy_quote(id)`
-- N'EST PAS touché ici : tenant CONCEPT différent (app.current_pharmacy_id,
-- déjà traité séparément depuis 0121) — hors scope explicite de cet audit
-- (cf. commentaire d'audit original sur #4291).
--
-- signature : quote.signature_id, prescription.signature_id — toutes deux
-- nullables (une signature n'existe qu'après l'action de signer).
--
-- Toutes les lignes existantes ont été insérées via une session déjà scopée
-- à un cabinet cohérent (RLS write, WITH CHECK cabinet_id) — la conversion
-- ne peut casser aucune ligne existante.
--
-- Vérifié contre Postgres réel (17.10 + pgTAP) : chaîne complète des 213
-- migrations + suite pgTAP intégrale, aucune régression.

ALTER TABLE quote
    ADD CONSTRAINT quote_id_cabinet_uniq UNIQUE (id, cabinet_id);

ALTER TABLE signature
    ADD CONSTRAINT signature_id_cabinet_uniq UNIQUE (id, cabinet_id);

ALTER TABLE quote_item
    DROP CONSTRAINT quote_item_quote_id_fkey;
ALTER TABLE quote_item
    ADD CONSTRAINT quote_item_quote_id_cabinet_fkey
    FOREIGN KEY (quote_id, cabinet_id)
    REFERENCES quote (id, cabinet_id);

ALTER TABLE payment_schedule
    DROP CONSTRAINT payment_schedule_quote_id_fkey;
ALTER TABLE payment_schedule
    ADD CONSTRAINT payment_schedule_quote_id_cabinet_fkey
    FOREIGN KEY (quote_id, cabinet_id)
    REFERENCES quote (id, cabinet_id);

ALTER TABLE payment
    DROP CONSTRAINT payment_quote_id_fkey;
ALTER TABLE payment
    ADD CONSTRAINT payment_quote_id_cabinet_fkey
    FOREIGN KEY (quote_id, cabinet_id)
    REFERENCES quote (id, cabinet_id);

ALTER TABLE treatment_plan
    DROP CONSTRAINT treatment_plan_quote_id_fkey;
ALTER TABLE treatment_plan
    ADD CONSTRAINT treatment_plan_quote_id_cabinet_fkey
    FOREIGN KEY (quote_id, cabinet_id)
    REFERENCES quote (id, cabinet_id);

ALTER TABLE quote
    DROP CONSTRAINT quote_signature_fk;
ALTER TABLE quote
    ADD CONSTRAINT quote_signature_id_cabinet_fkey
    FOREIGN KEY (signature_id, cabinet_id)
    REFERENCES signature (id, cabinet_id);

ALTER TABLE prescription
    DROP CONSTRAINT prescription_signature_id_fkey;
ALTER TABLE prescription
    ADD CONSTRAINT prescription_signature_id_cabinet_fkey
    FOREIGN KEY (signature_id, cabinet_id)
    REFERENCES signature (id, cabinet_id);
