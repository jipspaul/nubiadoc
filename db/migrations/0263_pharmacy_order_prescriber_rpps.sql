-- 0263_pharmacy_order_prescriber_rpps.sql
-- #6716 : le bandeau prescripteur de la vue pharmacie (Prescripteur / RPPS /
-- Prescrite le / Valable jusqu'au) affiche 3 tirets sur 4 — l'API n'a jamais
-- exposé le RPPS ni la date de prescription, alors que la donnée existe
-- (practitioner.rpps, prescription.signed_at/created_at).
--
-- prescriber_rpps/prescribed_at : SNAPSHOT au même titre que prescriber_name/
-- prescriber_practice (0245) — la pharmacie ne lit jamais practitioner ni
-- prescription en direct (RLS bornées au GUC cabinet), donc un live-join
-- depuis la vue pharmacie est impossible ; le créateur de la commande
-- (patient ou praticien) a le contexte cabinet nécessaire pour résoudre le
-- RPPS et la date de signature une seule fois, à la création.
-- "Valable jusqu'au" reste calculé à la lecture (prescribed_at + 3 mois,
-- durée de validité d'une ordonnance simple) : pas de colonne, la donnée ne
-- peut pas diverger.

ALTER TABLE pharmacy_order
    ADD COLUMN prescriber_rpps text,
    ADD COLUMN prescribed_at timestamptz;

COMMENT ON COLUMN pharmacy_order.prescriber_rpps IS
    'RPPS du prescripteur (practitioner.rpps), snapshot à la création — la pharmacie ne lit jamais practitioner en direct.';
COMMENT ON COLUMN pharmacy_order.prescribed_at IS
    'Date de prescription (prescription.signed_at, ou created_at à défaut), snapshot à la création.';

-- Backfill des commandes existantes : exécuté par nubia_owner (BYPASSRLS),
-- peut donc traverser prescription/practitioner librement.
UPDATE pharmacy_order po
SET prescriber_rpps = pr.rpps,
    prescribed_at = COALESCE(presc.signed_at, presc.created_at)
FROM prescription presc
JOIN practitioner pr ON pr.id = presc.practitioner_id
WHERE presc.id = po.prescription_id;
