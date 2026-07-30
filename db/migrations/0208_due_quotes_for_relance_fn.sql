-- 0208_due_quotes_for_relance_fn.sql
-- Fonction support du worker de relance des devis (#4126).
--
-- `quote` est une table TENANT (cabinet_id, RLS tenant_isolation), mais le
-- balayage des devis en attente de relance est intrinsèquement CROSS-CABINET
-- (un seul worker, tous les cabinets) — même besoin que
-- `due_reminders_for_dispatch` (migration 0156, #4034) : sans `app.
-- current_cabinet_id` posé, le worker Rust (pool nubia_app, RLS active) ne
-- verrait AUCUNE ligne via une simple SELECT sur `quote`.
--
-- SECURITY DEFINER (owner nubia_owner, BYPASSRLS) : ne renvoie que des
-- identifiants + un booléen dérivé (patient_account_id, jamais
-- patient_account brut), même garde que 0156/0123. Le worker Rust reste
-- responsable du set_config app.current_cabinet_id avant toute écriture
-- (quote_relance, notification) — RLS normale à l'écriture.
-- Issue : #4126

CREATE FUNCTION due_quotes_for_relance()
  RETURNS TABLE(
    quote_id           uuid,
    cabinet_id         uuid,
    patient_account_id uuid,
    days_since_sent    double precision
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET row_security = off
AS $$
  SELECT
    q.id,
    q.cabinet_id,
    p.patient_account_id,
    EXTRACT(EPOCH FROM (now() - q.sent_at)) / 86400
  FROM quote q
  JOIN patient p ON p.id = q.patient_id
  WHERE q.status = 'sent' AND q.sent_at IS NOT NULL AND q.deleted_at IS NULL
    AND q.sent_at <= now() - interval '3 days';
$$;

ALTER FUNCTION due_quotes_for_relance() OWNER TO nubia_owner;
REVOKE ALL ON FUNCTION due_quotes_for_relance() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION due_quotes_for_relance() TO nubia_app;
