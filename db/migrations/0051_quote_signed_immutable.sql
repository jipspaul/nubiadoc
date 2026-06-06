-- 0051_quote_signed_immutable.sql
-- Rend le devis (quote) immuable une fois signé (status='signed' ou signed_at renseigné).
-- Réf. : docs/05 §5.5, 0006_billing.sql, issue #760.

CREATE OR REPLACE FUNCTION enforce_quote_immutable()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status = 'signed' OR OLD.signed_at IS NOT NULL THEN
    RAISE EXCEPTION 'quote immuable : modification interdite après signature (id=%)', OLD.id
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER quote_signed_immutable
  BEFORE UPDATE ON quote
  FOR EACH ROW EXECUTE FUNCTION enforce_quote_immutable();
