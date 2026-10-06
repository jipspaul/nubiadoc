-- 0312_pharmacy_opening_hours.sql
-- #8061 : la carte pharmacie de l'écran de suivi de commande patient
-- (design-v2, encart 5 « Où est la pharmacie ? ») doit afficher les horaires
-- d'ouverture ET la distance — aucune colonne d'horaires n'existe sur
-- `pharmacy` (seul `cabinet.settings->>'horaires'` existe, 0002), donc rien
-- à exposer côté API quelle que soit la requête.
--
-- Même forme que `cabinet.settings->>'horaires'` : objet jsonb clé = jour
-- abrégé (lun/mar/mer/jeu/ven/sam/dim), valeur = plage "HH:MM-HH:MM" (clé
-- absente ou valeur absente = fermé ce jour-là).

ALTER TABLE pharmacy ADD COLUMN opening_hours JSONB NOT NULL DEFAULT '{}';
