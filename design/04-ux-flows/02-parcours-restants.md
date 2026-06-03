# Flux — Parcours restants

> Complète `01-wedge…`. Couvre les autres parcours du produit. Maquettes hi-fi de tous les écrans clés dans **`../mockups/nubia-maquettes.html`** (ouvrable au navigateur).
> Pour chaque parcours : objectif, étapes, états (vide/chargement/erreur), accessibilité.

## 1. Onboarding + compte (US-P01→P06)
- **Objectif** : créer son compte, donner ses consentements, compléter son profil.
- **Étapes** : invitation cabinet → création compte (e-mail + mot de passe / Face ID) → CGU + consentements (soins, notifications) → infos admin (coordonnées, sécu, mutuelle) → questionnaire médical.
- **États** : e-mail déjà utilisé (message clair), champ invalide, consentement requis bloquant, questionnaire repris plus tard.
- **A11y** : labels liés, erreurs annoncées, biométrie optionnelle.

## 2. Rendez-vous (US-P07→P12)
- **Objectif** : prendre/gérer un RDV sans appeler.
- **Étapes** : choisir motif → praticien → créneau dispo → confirmer → rappels J-1 (push/SMS) → modifier/annuler dans les délais. Demande de rappel cabinet. Liste d'attente (🎭).
- **États** : aucun créneau (proposer liste d'attente), annulation hors délai refusée, créneau pris entre-temps (rafraîchir).
- **A11y** : créneaux indisponibles non focusables, cibles ≥ 44 px.

## 3. Tableau de bord (US-P13, US-S02)
- **Patient** : prochain RDV, à signer, à régler, messages, questionnaires, actions — tuiles cliquables.
- **Secrétariat** : RDV du jour, messages urgents, devis en attente, **salle d'attente live** (WebSocket).
- **États** : vide (« rien à faire, tout est à jour »), chargement (squelette), compteurs exacts.

## 4. Messagerie (US-P15→P16, US-S06→S07, US-D06)
- **Objectif** : échanger patient ↔ cabinet, prioriser côté cabinet.
- **Étapes** : patient écrit (+ photo/doc) → triage **par règles** (flag urgent/non urgent **visuel**) → secrétariat traite / escalade niveau 3 praticien → réponse → conversion message → RDV en 1 clic.
- **Garde-fou** : le flag **priorise**, ne décide jamais (cf. `../../docs/03` §2). Bandeau 15/SAMU si urgence détectée, sans automatisme clinique.
- **États** : fil vide, pièce jointe en envoi, message non lu (point), erreur d'envoi (réessayer).

## 5. Dossier & coffre-fort (US-P17→P18)
- **Objectif** : retrouver et télécharger ses documents.
- **Étapes** : catégories (devis, ordo, radios/CBCT, CR, consentements) → ouvrir → télécharger (URL signée).
- **États** : catégorie vide, document indisponible, téléchargement en cours.
- **A11y** : chaque document est un élément focusable avec libellé explicite.

## 6. Espace financier + écrans démo (US-P21→P28)
- **Espace financier** (🟧) : devis/factures, reste à régler, **paiement acompte** (cf. wedge). Échéancier/financement (🎭).
- **Plan de traitement** (🎭) : soins faits/restants, étapes, coût global, reste à charge.
- **Passeport implantaire** (🎭) : marque/réf/lot/pose, export PDF (accent sable premium).
- **Suivi & prévention** (🟧) : rappels (détartrage, contrôle, implanto…), CTA « Prendre RDV ».
- **Infos cabinet** (🟧) : coordonnées, horaires, accès, **urgence 15/SAMU**.

## 7. Back-office — agenda & fiche patient (US-S01, US-S04, US-D01→D02)
- **Agenda** : vue jour/semaine, créneaux, déplacement de RDV, statut par pastille.
- **Fiche patient** : **vue praticien** (clinique) vs **vue secrétariat** (administratif) — cloisonnement R.4127-72 (US-X02).
- **États** : journée vide, conflit de créneau (anti-double-booking), patient introuvable.

## Transverse (US-X01→X04)
- **A11y** (X01) : contrastes AA, focus visible, lecteur d'écran, langue `fr`.
- **Cloisonnement** (X02) : vues distinctes selon rôle.
- **États vide/chargement/erreur** (X03) : systématiques sur chaque écran.
- **Démo investisseurs** (X04) : enchaînement scénarisé des 12 rubriques sur données fictives.

> Tous ces écrans sont rendus dans `../mockups/nubia-maquettes.html`. Prochaine itération design : critique (`design-critique`), microcopy (`../05-ux-copy/`), audit a11y (`../06-accessibilite/`).
