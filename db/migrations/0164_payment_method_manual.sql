-- 0164_payment_method_manual.sql
-- payment.method (migration 0055/0043) n'autorisait que
-- card/apple_pay/google_pay/sepa (paiements Stripe/GoCardless) : impossible
-- d'enregistrer un règlement espèces/chèque/virement reçu physiquement au
-- cabinet, alors que c'est un mode de paiement quotidien en cabinet
-- dentaire (#4070). Élargit le CHECK ; POST /v1/cabinet/payments/manual
-- (cabinet_payments_manual.rs) restreint côté API aux trois nouvelles
-- valeurs (jamais card/apple_pay/google_pay/sepa, qui doivent passer par
-- le flux PaymentIntent Stripe/GoCardless existant).

ALTER TABLE payment DROP CONSTRAINT IF EXISTS payment_method_check;
ALTER TABLE payment ADD CONSTRAINT payment_method_check
    CHECK (method IN ('card', 'apple_pay', 'google_pay', 'sepa', 'cash', 'check', 'bank_transfer'));
