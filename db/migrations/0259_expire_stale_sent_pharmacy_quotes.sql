-- 0259_expire_stale_sent_pharmacy_quotes.sql
-- #6607 : le correctif #6588 (migration de code seule, commit 3f763110)
-- n'expire les devis `sent` qu'AU MOMENT où la commande d'ancrage transitionne
-- vers picked_up/rejected/cancelled — il ne touche donc que les transitions
-- postérieures au déploiement. Les devis déjà bloqués sur une commande déjà
-- terminale AVANT le déploiement restent `sent` à vie (accept ET refuse
-- répondent 409 invalid_status, sans route de sortie). Rattrapage one-shot,
-- même règle que `expire_sent_quotes_for_order` (api/src/pharmacy/quotes.rs).

UPDATE pharmacy_quote q
SET status = 'expired', decided_at = now(), updated_at = now()
FROM pharmacy_order o
WHERE q.order_id = o.id
  AND q.status = 'sent'
  AND o.status IN ('picked_up', 'rejected', 'cancelled');
