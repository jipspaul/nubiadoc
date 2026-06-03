-- 0013_app_metadata.sql
-- Table de métadonnées applicatives globales (version, config).
-- Pas de RLS : table en lecture seule pour l'application (non tenant-scoped).
-- Issue : #20

CREATE TABLE app_metadata (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT INTO app_metadata (key, value) VALUES ('version', '0.1.0');

GRANT SELECT ON app_metadata TO nubia_app;
