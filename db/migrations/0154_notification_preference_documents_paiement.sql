-- 0154_notification_preference_documents_paiement.sql
-- Ajoute les topics "documents" et "paiement" à notification_preference (2 canaux
-- chacun : email/push, comme "messagerie"/"rappels" — pas de sms sur ces topics).
-- Le front expose 5 interrupteurs de catégorie (Rendez-vous/Documents/Messages/
-- Paiements/Prévention) mais seuls 3 topics existaient en base (rdv/messagerie/
-- rappels) : "Documents" et "Paiements" n'avaient aucun champ à persister, le
-- PATCH les droppait silencieusement (serde, champs inconnus non déclarés) et
-- ils repassaient à ON par défaut au rechargement — opt-out impossible (#3829).
-- Issue : #3829

ALTER TABLE notification_preference
  ADD COLUMN IF NOT EXISTS email_documents boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS push_documents  boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS email_paiement  boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS push_paiement   boolean NOT NULL DEFAULT true;
