-- 0247_user_notification_preference_push.sql
-- Ajoute les colonnes push_* à `user_notification_preference` (0246) :
-- le push mobile FCM (#6321) n'était pas réglable par catégorie, contraire à
-- la décision de l'épic #6256 (in-app/email/push réglables pour tous les
-- rôles). Additive uniquement, défaut ON comme in-app.
-- Issue : #6322

ALTER TABLE user_notification_preference
  ADD COLUMN push_rdv         boolean NOT NULL DEFAULT true,
  ADD COLUMN push_messagerie  boolean NOT NULL DEFAULT true,
  ADD COLUMN push_devis       boolean NOT NULL DEFAULT true,
  ADD COLUMN push_stock       boolean NOT NULL DEFAULT true,
  ADD COLUMN push_labo        boolean NOT NULL DEFAULT true,
  ADD COLUMN push_visites     boolean NOT NULL DEFAULT true;
