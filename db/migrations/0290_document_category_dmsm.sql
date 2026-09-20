-- 0290_document_category_dmsm.sql
-- [DP-F17.b] Conformité ARS/DMSM (#7170) : `document.category` accepte
-- `dmsm` — la déclaration de dispositif médical sur mesure générée par
-- `POST /v1/patients/:id/custom-device-declarations` (`compliance.rs`) est
-- stockée comme document patient (mécanisme `document` existant, même
-- pattern que `courrier`/`consentement`, migration 0267). Catégorie
-- administrative (déclaration réglementaire, pas un jugement clinique) :
-- ajoutée à `NON_CLINICAL_CATEGORIES` côté API.

ALTER TABLE document DROP CONSTRAINT document_category_check;
ALTER TABLE document ADD CONSTRAINT document_category_check
    CHECK (category IN (
        'devis', 'facture', 'ordonnance', 'radio', 'cbct', 'photo', 'cr',
        'consigne', 'attestation', 'carte_mutuelle', 'passeport_implantaire',
        'consentement', 'courrier', 'dmsm'
    ));
