-- 0250_object_storage_blob.sql
-- Coffre-fort : back-end `ObjectStorage` persistant (#6453).
--
-- Contexte : `infra/deploy/deploy.sh` recrée le conteneur `nubia-api` à chaque
-- déploiement (`podman rm -f` + `podman run`) sans volume monté, contrairement
-- à `nubia-pg` (`-v nubia_pg:/var/lib/postgresql/data`). Un `ObjectStorage`
-- en mémoire (ou sur le filesystem du conteneur API) ne survit donc à aucun
-- redéploiement. Postgres est le seul composant réellement persistant de
-- cette topologie : les objets binaires (PDF d'ordonnance, etc.) sont donc
-- stockés ici, la table `document` ne référençant que la clé (`storage_key`).
--
-- Pas de RLS : cette table n'est pas tenant-scoped (clé opaque, même
-- sémantique qu'un vrai object storage S3) — le contrôle d'accès est fait en
-- amont, côté application, sur la ligne `document` (RLS tenant) avant toute
-- lecture/écriture ici.
CREATE TABLE object_storage_blob (
  key          text PRIMARY KEY,
  content_type text NOT NULL,
  bytes        bytea NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);
