-- 0227_prescription_item_pharmacy_read.sql
-- RLS pharmacie sur prescription_item (#4876) : lire les lignes de
-- l'ordonnance (molécule, posologie, quantité, substituable ou non) est le
-- métier du pharmacien — jusqu'ici seule policy pharmacie existante était
-- document_pharmacy_read (0124, PDF uniquement), pas les lignes structurées.
-- Même pattern que 0124 : bornée aux commandes de la pharmacie courante
-- (app.current_pharmacy_id), fail-closed. Le cycle de vie (cancelled/rejected)
-- est filtré côté application (get_pharmacy_order_items), pas ici — comme
-- pour document_pharmacy_read.
-- Minimisation : pas de policy équivalente sur `prescription` elle-même
-- (patient_id, etc.) — seule prescription_item est exposée à la pharmacie.
-- Issue : #4876

CREATE POLICY prescription_item_pharmacy_read ON prescription_item
  FOR SELECT TO nubia_app
  USING (
    prescription_id IN (
      SELECT prescription_id FROM pharmacy_order
      WHERE pharmacy_id = nullif(current_setting('app.current_pharmacy_id', true), '')::uuid
    )
  );
