-- 0270_letter_template_fix_double_titre.sql
-- #7241 : `{{praticien.nom}}` (résolu via `practitioner_display_name()`,
-- migration 0258) rend déjà le nom d'exercice titré (« Dr Hugo Marin » —
-- même valeur que `/v1/search/providers`). Les 3 modèles globaux seedés par
-- 0267 préfixaient en plus « Dr » en dur devant le placeholder, produisant
-- « Dr Dr Hugo Marin » à la substitution. Migration immuable (règle
-- `db/migrations/README.md`) : correction via UPDATE plutôt que retouche de
-- 0267.

UPDATE letter_template SET body_template =
  E'Madame, Monsieur {{patient.prenom}} {{patient.nom}},\n\nNous vous confirmons votre rendez-vous au cabinet {{cabinet.nom}} le {{rdv.date}} à {{rdv.heure}}, avec le {{praticien.nom}}.\n\nEn cas d''empêchement, merci de nous prévenir au plus tôt au {{cabinet.telephone}}.\n\nNous vous prions d''agréer, Madame, Monsieur, l''expression de nos salutations distinguées.\n\nLe secrétariat'
WHERE id = '02670000-0000-0000-0000-000000000001';

UPDATE letter_template SET body_template =
  E'Cher confrère, chère consœur {{correspondant.nom}},\n\nJe me permets de vous adresser {{patient.prenom}} {{patient.nom}}, né(e) le {{patient.date_naissance}}, que je suis au cabinet {{cabinet.nom}}.\n\nJe vous remercie par avance de bien vouloir le/la recevoir et reste à votre disposition pour tout complément d''information.\n\nBien confraternellement,\n\n{{praticien.nom}}\nRPPS {{praticien.rpps}}'
WHERE id = '02670000-0000-0000-0000-000000000003';

UPDATE letter_template SET body_template =
  E'Je soussigné(e), {{praticien.nom}} (RPPS {{praticien.rpps}}), atteste que {{patient.prenom}} {{patient.nom}}, né(e) le {{patient.date_naissance}}, s''est présenté(e) au cabinet {{cabinet.nom}} le {{rdv.date}} à {{rdv.heure}}.\n\nAttestation établie à la demande de l''intéressé(e) pour faire valoir ce que de droit.\n\nFait le {{date.aujourdhui}}.\n\n{{praticien.nom}}'
WHERE id = '02670000-0000-0000-0000-000000000004';
