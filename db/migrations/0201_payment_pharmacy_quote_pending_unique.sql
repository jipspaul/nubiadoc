-- 0201_payment_pharmacy_quote_pending_unique.sql
-- Empeche deux paiements pending/paid concurrents sur le meme devis
-- pharmacie (#4418) : POST /payments/pharmacy-quote-intent verifiait le
-- reste-du en lecture seule (SUM(...) puis INSERT), sans verrou -- sous READ
-- COMMITTED, deux requetes concurrentes avec deux Idempotency-Key distinctes
-- lisent chacune committed=0 < total_cents et inserent chacune un paiement
-- plein-montant (double-charge). La RLS pharmacy_quote_patient_update
-- n'autorise FOR UPDATE que sur status='sent' (un devis deja 'accepted'
-- deviendrait invisible sous verrou) -- impossible de fermer la race avec un
-- verrou applicatif ici. L'index unique partiel ferme la race au niveau DB,
-- independamment de tout timing applicatif : au plus UN paiement
-- pending/paid par devis pharmacie.
--
-- Corrige avant premiere application reussie (echec en prod le 2026-07-28,
-- jamais applique nulle part de facon persistante -- CI recree sa DB a
-- chaque run, sans etat a faire diverger) : des paiements pending/paid
-- dupliques preexistaient deja (exactement la race que ce fix corrige,
-- survenue AVANT son propre deploiement -- y compris le devis 762d97a4 du
-- repro de #4418 lui-meme), rendant la creation de l'index impossible
-- (unique_violation). On neutralise d'abord les doublons : pour chaque
-- pharmacy_quote_id avec plusieurs paiements pending/paid, seul le plus
-- ancien (created_at) reste actif, les autres passent a 'failed' (aucune
-- retro-facturation, juste desactivation de la ligne excedentaire vis-a-vis
-- de la contrainte -- l'historique reste consultable).
WITH ranked AS (
  SELECT id, row_number() OVER (
    PARTITION BY pharmacy_quote_id ORDER BY created_at ASC, id ASC
  ) AS rn
  FROM payment
  WHERE pharmacy_quote_id IS NOT NULL AND status IN ('pending', 'paid')
)
UPDATE payment SET status = 'failed'
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

CREATE UNIQUE INDEX payment_pharmacy_quote_pending_unique
  ON payment (pharmacy_quote_id)
  WHERE pharmacy_quote_id IS NOT NULL AND status IN ('pending', 'paid');
