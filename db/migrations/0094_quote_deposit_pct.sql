-- 0094_quote_deposit_pct.sql
-- Ajoute quote.deposit_pct : pourcentage d'acompte demandé au patient (0..100).
-- Utilisé par POST /v1/cabinet/quotes (issue #1664).
ALTER TABLE quote
  ADD COLUMN IF NOT EXISTS deposit_pct numeric(5,2) CHECK (deposit_pct >= 0 AND deposit_pct <= 100);
