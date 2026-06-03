-- 0006_billing.sql
-- Wedge : devis, signature, échéancier, paiement. Réf. : docs/05 §5.5.
-- Argent : numeric(12,2) + currency char(3) (jamais de float). L'API expose en
-- centimes entiers (docs/12 §1.1) ; conversion à la frontière applicative.

CREATE TABLE quote (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id    uuid NOT NULL REFERENCES cabinet(id),
  patient_id    uuid NOT NULL REFERENCES patient(id),
  version       int  NOT NULL DEFAULT 1,
  status        text NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','sent','signed','refused','expired')),
  total_amount  numeric(12,2) NOT NULL DEFAULT 0,
  currency      char(3) NOT NULL DEFAULT 'EUR',
  -- immutabilité une fois signé (empreinte du PDF signé)
  signed_at     timestamptz,
  signed_sha256 char(64),
  signature_id  uuid,                    -- FK posée après création de signature (ci-dessous)
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  deleted_at    timestamptz
);

CREATE TABLE quote_item (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id  uuid NOT NULL REFERENCES cabinet(id),
  quote_id    uuid NOT NULL REFERENCES quote(id),
  label       text NOT NULL,
  ccam_code   text,
  tooth       text,                     -- dent concernée (FDI)
  qty         numeric(6,2) NOT NULL DEFAULT 1,
  unit_amount numeric(12,2) NOT NULL,
  amc_part    numeric(12,2),            -- prise en charge mutuelle estimée
  amo_part    numeric(12,2)             -- part assurance maladie obligatoire
);

CREATE TABLE signature (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id   uuid NOT NULL REFERENCES cabinet(id),
  provider     text NOT NULL DEFAULT 'yousign',
  provider_ref text NOT NULL,
  level        text NOT NULL DEFAULT 'aes',   -- eIDAS advanced
  certificate  jsonb,                          -- éléments probants
  signed_at    timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- FK différée de quote -> signature (les deux tables existent maintenant).
ALTER TABLE quote
  ADD CONSTRAINT quote_signature_fk FOREIGN KEY (signature_id) REFERENCES signature(id);

CREATE TABLE payment_schedule (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id   uuid NOT NULL REFERENCES cabinet(id),
  patient_id   uuid NOT NULL REFERENCES patient(id),
  quote_id     uuid REFERENCES quote(id),
  total_amount numeric(12,2) NOT NULL,
  installments jsonb NOT NULL DEFAULT '[]',   -- jalons {date, montant, statut}
  provider     text,                           -- stripe, gocardless, alma (post-MVP)
  status       text NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active','completed','cancelled')),
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE payment (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cabinet_id      uuid NOT NULL REFERENCES cabinet(id),
  patient_id      uuid NOT NULL REFERENCES patient(id),
  schedule_id     uuid REFERENCES payment_schedule(id),
  quote_id        uuid REFERENCES quote(id),
  amount          numeric(12,2) NOT NULL,
  currency        char(3) NOT NULL DEFAULT 'EUR',
  kind            text NOT NULL CHECK (kind IN ('deposit','installment','full')),
  provider        text NOT NULL,           -- stripe, gocardless
  provider_ref    text,
  status          text NOT NULL CHECK (status IN ('pending','paid','failed','refunded')),
  idempotency_key text,
  created_at      timestamptz NOT NULL DEFAULT now()
);
