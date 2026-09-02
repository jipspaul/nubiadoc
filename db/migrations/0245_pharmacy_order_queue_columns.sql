-- 0245_pharmacy_order_queue_columns.sql
-- #6253 (reliquat de #6168) : la file pharmacie (design-v2) attend un
-- prescripteur, un n° de commande et un nombre de lignes par rangée — le
-- front (orders_page.dart/order_row.dart) sait déjà les afficher (#4926,
-- #5349) mais l'API n'a jamais exposé les 3 champs, d'où des colonnes
-- vides depuis toujours.
--
-- prescriber_name/prescriber_practice : SNAPSHOT au même titre que
-- pharmacy_name/patient_display_name (déjà sur cette table, 0124) — la
-- pharmacie ne lit jamais `cabinet`/`practitioner` (RLS bornées au GUC
-- cabinet, cf. 0011), donc un live-join depuis la vue pharmacie est
-- impossible ; à l'inverse le créateur de la commande (patient ou
-- praticien, prescription_send.rs) a le contexte cabinet nécessaire pour
-- résoudre ces noms une seule fois, à la création.
-- order_seq : compteur global (identity), formaté `CMD-0042` à la lecture
-- (api/src/pharmacy/orders.rs) — même logique que audit_log.id (0008).
-- line_count reste calculé à la lecture (COUNT sur prescription_item, déjà
-- lisible par la pharmacie via prescription_item_pharmacy_read, 0227) : pas
-- besoin de colonne, la donnée ne peut pas diverger.

ALTER TABLE pharmacy_order
    ADD COLUMN order_seq bigint GENERATED ALWAYS AS IDENTITY,
    ADD COLUMN prescriber_name text,
    ADD COLUMN prescriber_practice text;

COMMENT ON COLUMN pharmacy_order.order_seq IS
    'Compteur global, formaté "CMD-0042" à la lecture (order_ref). Jamais exposé brut.';
COMMENT ON COLUMN pharmacy_order.prescriber_name IS
    'Nom du prescripteur (provider.display_name), snapshot à la création — la pharmacie ne lit jamais practitioner/provider en direct. NULL si le praticien n''a pas de profil provider.';
COMMENT ON COLUMN pharmacy_order.prescriber_practice IS
    'Raison sociale du cabinet prescripteur, snapshot à la création (même contrainte RLS que prescriber_name).';

-- Backfill des commandes existantes : exécuté par nubia_owner (BYPASSRLS),
-- peut donc traverser prescription/practitioner/provider/cabinet librement.
UPDATE pharmacy_order po
SET prescriber_name = prov.display_name,
    prescriber_practice = c.raison_sociale
FROM prescription presc
JOIN cabinet c ON c.id = presc.cabinet_id
LEFT JOIN provider prov ON prov.practitioner_id = presc.practitioner_id
WHERE presc.id = po.prescription_id;
