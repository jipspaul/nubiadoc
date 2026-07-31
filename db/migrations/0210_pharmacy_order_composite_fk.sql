-- 0210_pharmacy_order_composite_fk.sql
-- #4291 : pharmacy_order était explicitement signalé comme le cas le plus
-- urgent de l'audit — table pont cross-tenant (pharmacie/patient/cabinet)
-- dont 3 FK vers des tables cabinet/patient-scopées restaient simples.
-- PostgreSQL fait bypasser la RLS aux vérifications FK (documenté § Row
-- Security Policies) : une session sous le GUC du cabinet B pouvait créer un
-- pharmacy_order référençant un document/prescription du cabinet A, invisible
-- en SELECT sous ce même GUC. document_id est le vecteur le plus sensible :
-- c'est le PDF exposé à la pharmacie (policy document_pharmacy_read) — un
-- document_id cross-cabinet est un vecteur de fuite documentaire clinique
-- direct.
--
-- document/prescription : cabinet_id + RLS (0011) → composite (id, cabinet_id)
-- comme les fix précédents (0190/0198/0334/0385).
--
-- consent_record : cas différent, PAS cabinet-scopé (refactor 0017 — devenu
-- plateforme app_user_id/patient_account_id, RLS account-scoped, cf. 0048).
-- pharmacy_order.consent_record_id référençait donc consent_record(id) sans
-- aucune dimension tenant partagée avec cabinet_id — le risque analogue ici
-- n'est pas cross-cabinet mais cross-PATIENT (référencer le consentement
-- d'un AUTRE patient). Toujours généré serveur dans le flux actuel
-- (prescription_send.rs, jamais fourni par le client), donc pas exploitable
-- aujourd'hui, mais l'invariant DB doit exister indépendamment du code
-- applicatif (c'est tout le point de #4291). Fix analogue avec
-- patient_account_id au lieu de cabinet_id : UNIQUE (id, patient_account_id)
-- sur consent_record + FK composite (consent_record_id, patient_account_id).
--
-- Toutes les colonnes FK simples remplacées sont déjà correctement peuplées
-- par le seul chemin d'écriture existant (pharmacy/orders.rs, prescription_
-- send.rs) : la conversion ne peut casser aucune ligne existante.
--
-- Vérifié contre Postgres réel (16.14) sur un schéma minimal reproduisant les
-- 4 tables concernées : insert légitime même-cabinet/même-patient accepté,
-- exploit cross-cabinet (document_id d'un autre cabinet) et exploit
-- cross-patient (consent_record_id d'un autre patient) tous deux bloqués en
-- 23503 après ce fix (passaient avant, réplication manuelle de l'exploit).

ALTER TABLE document
    ADD CONSTRAINT document_id_cabinet_uniq UNIQUE (id, cabinet_id);

ALTER TABLE prescription
    ADD CONSTRAINT prescription_id_cabinet_uniq UNIQUE (id, cabinet_id);

ALTER TABLE consent_record
    ADD CONSTRAINT consent_record_id_account_uniq UNIQUE (id, patient_account_id);

ALTER TABLE pharmacy_order
    DROP CONSTRAINT pharmacy_order_document_id_fkey;
ALTER TABLE pharmacy_order
    ADD CONSTRAINT pharmacy_order_document_id_cabinet_fkey
    FOREIGN KEY (document_id, cabinet_id)
    REFERENCES document (id, cabinet_id);

ALTER TABLE pharmacy_order
    DROP CONSTRAINT pharmacy_order_prescription_id_fkey;
ALTER TABLE pharmacy_order
    ADD CONSTRAINT pharmacy_order_prescription_id_cabinet_fkey
    FOREIGN KEY (prescription_id, cabinet_id)
    REFERENCES prescription (id, cabinet_id);

ALTER TABLE pharmacy_order
    DROP CONSTRAINT pharmacy_order_consent_record_id_fkey;
ALTER TABLE pharmacy_order
    ADD CONSTRAINT pharmacy_order_consent_record_id_account_fkey
    FOREIGN KEY (consent_record_id, patient_account_id)
    REFERENCES consent_record (id, patient_account_id);
