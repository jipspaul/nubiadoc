-- 0321_prescription_item_prepared.sql
-- jips/nubiadoc#6783 : « La préparation se coche » (Pharmacie Delivrance v2.html,
-- point 7) — une case par ligne + compteur « X sur Y préparées » qui conditionne
-- preparing → ready. Le geste existait déjà côté front (#4882) mais purement en
-- mémoire (perdu au moindre rechargement) : prescription_item n'a aucune colonne
-- pour le persister, donc rien ne trace réellement ce qui a été sorti des rayons.

ALTER TABLE prescription_item
    ADD COLUMN prepared boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN prescription_item.prepared IS
    'Ligne sortie des rayons par le pharmacien pendant la préparation (#6783). Bascule via POST /v1/pharmacy/orders/{id}/items/{item_id}/prepared, gatée sur pharmacy_order.status = ''preparing'' côté API.';
