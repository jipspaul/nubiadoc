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
CREATE UNIQUE INDEX payment_pharmacy_quote_pending_unique
  ON payment (pharmacy_quote_id)
  WHERE pharmacy_quote_id IS NOT NULL AND status IN ('pending', 'paid');
