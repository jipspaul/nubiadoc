-- 0004_documents.sql
-- Documents & coffre-fort. Réf. : docs/05 §5.3, §10.9.
-- Le binaire est dans l'Object Storage (chiffré au repos + URLs signées) ; la base
-- ne stocke que les métadonnées + l'empreinte d'intégrité.

CREATE TABLE document (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id  uuid NOT NULL REFERENCES cabinet(id),
  patient_id  uuid REFERENCES patient(id),
  category    text NOT NULL CHECK (category IN (
                'devis','facture','ordonnance','radio','cbct','photo','cr',
                'consigne','attestation','carte_mutuelle','passeport_implantaire',
                'consentement')),
  storage_key text NOT NULL,        -- clé Object Storage (objet chiffré)
  filename    text NOT NULL,
  mime_type   text NOT NULL,
  sha256      char(64) NOT NULL,    -- intégrité
  uploaded_by uuid REFERENCES app_user(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  deleted_at  timestamptz
);
