# Ateliers produit — suivi

Journal des ateliers produit avec les associés et les experts métier.
Un fichier par séance, plus ce README qui porte **l'état courant** : décisions
prises, arbitrages en attente, actions ouvertes.

> **Ce README est la seule page à lire pour savoir où on en est.**
> Les comptes rendus de séance sont l'historique, pas l'état.

## Convention

| | |
|---|---|
| Compte rendu | `docs/ateliers/AAAA-MM-JJ-<sujet>.md`, un par séance |
| Gabarit | [`TEMPLATE.md`](TEMPLATE.md) — copier avant chaque séance |
| Transcription brute | `docs/ateliers/transcriptions/AAAA-MM-JJ-*.txt` — **non versionnée** (cf. le `.gitignore` du dossier) |
| Identifiants | Décisions `D-nn`, actions `A-nn`, arbitrages en attente `Q-nn` — numérotation continue, jamais réutilisée |

Après chaque séance : écrire le CR, puis **remonter les nouvelles lignes dans
les trois tableaux ci-dessous** et rayer ce qui est clos. Les tâches qui
deviennent du code partent en issue Forgejo et le tableau garde le numéro.

## Séances

| Date | Sujet | Participants | CR |
|---|---|---|---|
| 2026-09-08 | Cadrage produit avec Abir Talbi — priorisation logiciel métier | Xavier Barraud, Jean-Paul Jacquot, Abir Talbi | [CR](2026-09-08-cadrage-logiciel-metier.md) · [version publiée](https://claude.ai/code/artifact/e0016ce3-853e-46df-b7a7-74b8bbc2225f) |

Rythme convenu : **tous les mardis 14 h – 16 h**, à partir du 2026-09-15.

## Décisions actées

| # | Décision | Séance | Conséquence |
|---|---|---|---|
| D-01 | Le logiciel métier passe avant les modules périphériques | 2026-09-08 | Réordonne toute la roadmap ; déclenche `Q-01` |
| D-02 | Nubia vise le **remplacement** du logiciel métier, pas la sur-couche | 2026-09-08 | Invalide la posture de `docs/15-decision-sesam-vitale.md` §4 |
| D-03 | L'IA reste une option payante, jamais activée par défaut, avec choix local / cloud | 2026-09-08 | Cadre le lot 8 ; évite le contrecoup subi par Doctolib |
| D-04 | Statuts et pacte d'associés rédigés maintenant, sans attendre la traction | 2026-09-08 | Préalable à l'apport des modules d'Abir (`A-04`) |

## Arbitrages en attente

Ce qui bloque du travail tant que ce n'est pas tranché.

| # | Question | Bloque | Porteur | Depuis |
|---|---|---|---|---|
| Q-01 | Rejouer `docs/15` (SESAM-Vitale) : middleware agréé, build en propre, ou statu quo ? | Lot 7, et le discours commercial | Xavier | 2026-09-08 |
| Q-02 | Rejouer `docs/16` (tiers payant) : agrégateur dédié ou couplé au choix FSE ? | Lot 3 (prise en charge), lot 7 | Xavier | 2026-09-08 |
| Q-03 | Quelle cible Ségur exactement — vague, couloir, prérequis, montant par praticien ? Base de départ : `docs/07-conformite.md` §9, déjà instruit | Chiffrage du lot 7 | Abir | 2026-09-08 |
| Q-04 | Statut du code des deux modules d'Abir : apport en nature, cession, ou licence ? | Lot 3 | Xavier + Abir | 2026-09-08 |
| Q-05 | Le paiement en ligne patient et l'acompte à distance sont-ils licites en l'état ? | Lot 3 (acompte) | Abir | 2026-09-08 |

## Actions ouvertes

| # | Action | Porteur | Échéance | État |
|---|---|---|---|---|
| A-01 | Fournir la grille CCAM annotée : panier 100 % Santé, plafond opposable, prérequis documentaire, incompatibilités | Abir | 2026-09-15 | ouvert |
| A-02 | Fournir la grille de contrôle ARS complète | Abir | à planifier | ouvert |
| A-03 | Fournir les règles de rappel clinique (quel acte → quelle relance → à quelle échéance) | Abir | à planifier | ouvert |
| A-04 | Démontrer les deux modules « prise en charge mutuelle » et « rejets » | Abir | 2026-09-15 | ouvert |
| A-05 | Chiffrer Icanopée et jFSE : coût par praticien, délai, périmètre FSE + DRE + NOÉMIE | Xavier | 2026-09-15 | ouvert |
| A-06 | Rédiger statuts + pacte d'associés | Xavier | à planifier | ouvert |
| A-07 | Instruire les pistes de financement : FEDER, régional, appels à projets ARS / Sécu | Xavier | à planifier | ouvert |
| A-08 | Ouvrir les issues Forgejo des lots 1 et 2, à la maille livrable | Jean-Paul | 2026-09-15 | ouvert |
| A-09 | Préparer le format d'import de la grille CCAM pour qu'Abir la remplisse sans friction | Jean-Paul | 2026-09-15 | ouvert |
| A-10 | Finir et merger les branches `agent/design-ecran-*` en attente | Jean-Paul | à planifier | ouvert |
| A-11 | Réviser `docs/15` et `docs/16` une fois `Q-01` / `Q-02` tranchés | Jean-Paul | après Q-01 | bloqué |

## Roadmap issue de ces ateliers

L'ordre des lots et leur contenu vivent dans le CR du 2026-09-08
([§ Plan d'attaque](2026-09-08-cadrage-logiciel-metier.md#5-plan-dattaque)).
Toute modification de cet ordre est une décision : l'ajouter au tableau `D-nn`.
