-- 0309_pharmacy_quote_reminder_trace.sql
-- #6900 : `POST /v1/pharmacy/quotes/:id/remind` répondait 200 et renotifiait
-- bien le patient, mais sans laisser aucune trace sur le devis — l'écran
-- pharmacie n'avait donc rien à afficher de différent après le clic (l'objet
-- renvoyé était strictement identique), et rien n'empêchait trois relances
-- en rafale (79 ms) d'envoyer trois notifications identiques au patient.
--
-- `reminded_at`/`reminder_count` donnent au handler de quoi (a) refléter la
-- relance dans la réponse (et donc à l'écran) et (b) appliquer un cooldown
-- server-side entre deux relances du même devis.

ALTER TABLE pharmacy_quote ADD COLUMN reminded_at TIMESTAMPTZ;
ALTER TABLE pharmacy_quote ADD COLUMN reminder_count INT NOT NULL DEFAULT 0;
