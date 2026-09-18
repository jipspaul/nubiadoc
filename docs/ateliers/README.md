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
| 2026-09-16 | Périmètre minimal : tester vite, en réseau local — roadmap pour le 18/09 | Xavier Barraud, Jean-Paul Jacquot | [CR](2026-09-16-perimetre-mvp-reseau-local.md) · [version publiée](https://claude.ai/artifact/GRquaSrp2tTFWaGWr5TNpf) |
| 2026-09-18 | Périmètre initial : de la carte Vitale à la facture — jalon J1 | Xavier Barraud, Jean-Paul Jacquot, Abir Talbi | [CR](2026-09-18-perimetre-initial-logiciel-dentaire.md) |

Rythme convenu : **tous les mardis 14 h – 16 h**, à partir du 2026-09-15.

## Décisions actées

| # | Décision | Séance | Conséquence |
|---|---|---|---|
| D-01 | Le logiciel métier passe avant les modules périphériques | 2026-09-08 | Réordonne toute la roadmap ; déclenche `Q-01` |
| D-02 | Nubia vise le **remplacement** du logiciel métier, pas la sur-couche | 2026-09-08 | Invalide la posture de `docs/15-decision-sesam-vitale.md` §4 |
| D-03 | L'IA reste une option payante, jamais activée par défaut, avec choix local / cloud | 2026-09-08 | Cadre le lot 8 ; évite le contrecoup subi par Doctolib |
| D-04 | Statuts et pacte d'associés rédigés maintenant, sans attendre la traction | 2026-09-08 | Préalable à l'apport des modules d'Abir (`A-04`) |
| D-05 | Le MVP tourne sur un **serveur dans le réseau local** du centre pilote, pas sur un VPS | 2026-09-16 | `infra/deploy` = base de la box ; app patient à distance hors MVP (`Q-06`) |
| D-06 | Aucune donnée de santé ne transite par internet public sans hébergement certifié | 2026-09-16 | Services externes coupés sur la box ; canaux sortants à instruire (`Q-08`) |
| D-07 | Pilotage à distance **technique seulement** : état serveurs + logs anonymisés, partition séparée, OpenTelemetry | 2026-09-16 | Condition de l'analyse HDS ; scrubbing PII des logs obligatoire |
| D-08 | Déclencheurs d'événements et règles de cotation légales **spécifiés et vérifiés en TLA+** | 2026-09-16 | Garantie interne, jamais présentée comme certification |
| D-09 | La **cotation reste le chemin critique** (reconduit D-01), explicite dans le périmètre minimal | 2026-09-16 | Socle 2 de la roadmap du 16/09 |
| D-10 | LLM local pour les comptes rendus = option post-MVP, conditionnée au matériel | 2026-09-16 | Hors roadmap fin d'année |
| D-11 | **Premier jalon J1** = dossier patient complet depuis la carte Vitale, facturé après validation des droits, avant tout travail sur les actes | 2026-09-18 | Remplace la cotation comme chemin critique ; roadmap réordonnée (CR 18/09 §6) |
| D-12 | Périmètre initial = **secrétariat + praticien** ; échanges avec les patients exclus | 2026-09-18 | Tranche Q-06 (app patient hors MVP) ; Q-08 sort du chemin critique |
| D-13 | La cotation démarre par **trois actes** (consultation, détartrage haut, détartrage bas) ; le reste en phase ultérieure | 2026-09-18 | A-01 passe après J1 ; A-36 la remplace pour J1 |
| D-14 | Tests **en local, sans internet**, dans un centre réel, avec vrais lecteurs et vraies cartes | 2026-09-18 | La box (A-16) est le support de la recette J1 |
| D-15 | Majorations nuit / dimanche **détectées, jamais appliquées d'office** ; le praticien confirme selon un paramètre de sa fiche | 2026-09-18 | Champ fiche praticien (A-34) + règle de cotation |
| D-16 | Lecture de la carte mutuelle pour les devis ≠ création du dossier ; le module de prise en charge d'Abir est **à retravailler** avant usage | 2026-09-18 | Socle 4 « argent » repoussé après le pilote |
| D-17 | Données mutuelle et taux AMO / AMC **auto-renseignés quand possible, toujours corrigeables** à la main | 2026-09-18 | Contrainte de conception de l'écran couverture |
| D-18 | **Vizia** = référence fonctionnelle ; Desmos = référence d'ouverture | 2026-09-18 | Les écrans J1 se comparent à Vizia |

## Arbitrages en attente

Ce qui bloque du travail tant que ce n'est pas tranché.

| # | Question | Bloque | Porteur | Depuis |
|---|---|---|---|---|
| Q-01 | Rejouer `docs/15` (SESAM-Vitale) : middleware agréé, build en propre, ou statu quo ? | Lot 7, et le discours commercial | Xavier | 2026-09-08 |
| Q-02 | Rejouer `docs/16` (tiers payant) : agrégateur dédié ou couplé au choix FSE ? | Lot 3 (prise en charge), lot 7 | Xavier | 2026-09-08 |
| Q-03 | Quelle cible Ségur exactement — vague, couloir, prérequis, montant par praticien ? Base de départ : `docs/07-conformite.md` §9, déjà instruit | Chiffrage du lot 7 | Abir | 2026-09-08 |
| Q-04 | Statut du code des deux modules d'Abir : apport en nature, cession, ou licence ? | Lot 3 | Xavier + Abir | 2026-09-08 |
| Q-05 | Le paiement en ligne patient et l'acompte à distance sont-ils licites en l'état ? | Lot 3 (acompte) | Abir | 2026-09-08 |
| ~~Q-06~~ | ~~Interface patient dans un MVP LAN~~ — **tranchée le 2026-09-18 (D-12) : hors MVP** | — | — | 2026-09-16 |
| Q-07 | Ce qu'on peut faire avec de **vraies données sans certification** : HDS pour compte de tiers, AIPD du centre, statut de Nubia (sous-traitant ou non), contrat de pilote — à valider par un juriste | Bascule données réelles (socle 1) | Xavier | 2026-09-16 |
| Q-08 | Canaux sortants autorisés depuis la box : un SMS « date, heure, adresse » seulement est-il acceptable ? Quel opérateur, quel DPA ? | Rappels (socle 3), signature devis | Xavier + Abir | 2026-09-16 |
| Q-09 | Groupe d'Abir : une entité juridique ou plusieurs ? Un serveur central + VPN site-à-site, ou un serveur par centre ? | Multi-site, analyse HDS §4.1 | Abir | 2026-09-16 |
| Q-10 | Matériel de la box : qui achète, qui installe, spec (disque, onduleur ; GPU si LLM local) ? | Socle 1 | Xavier + Abir | 2026-09-16 |
| Q-11 | **À quelles conditions lire une carte Vitale** sans agrément SESAM-Vitale : carte pro + code porteur suffisent-ils, quels justificatifs, quel statut pour Nubia ? | J1 étape 1 | Équipe (Abir justificatifs, Jean-Paul technique) | 2026-09-18 |
| Q-12 | **PIX Vitale** (Desmos) : payant ? autorisé pour les essais ? source de données ou référence de format ? | J1 étape 1 | Abir → Desmos | 2026-09-18 |
| Q-13 | **Orisha** ou prestataire similaire pour la facturation / connexion technique ? Conditions d'accès aux éléments techniques. Rejoue Q-01 (`docs/15` excluait Orisha) | J1 étape 5 au-delà du papier, lot 7 | Abir → Guillaume | 2026-09-18 |
| Q-14 | Cartes de recette : jeu de test du GIE SESAM-Vitale ou cartes réelles des testeurs (= données réelles, Q-07) ? | Recette J1 | Xavier | 2026-09-18 |

## Actions ouvertes

| # | Action | Porteur | Échéance | État |
|---|---|---|---|---|
| A-01 | Fournir la grille CCAM annotée : panier 100 % Santé, plafond opposable, prérequis documentaire, incompatibilités | Abir | ~~2026-09-15~~ ~~2026-09-18~~ → 2026-10-23 | **après J1** (D-13) ; A-36 la remplace pour J1 |
| A-02 | Fournir la grille de contrôle ARS complète | Abir | à planifier | ouvert |
| A-03 | Fournir les règles de rappel clinique (quel acte → quelle relance → à quelle échéance) | Abir | à planifier | ouvert |
| A-04 | Démontrer les deux modules « prise en charge mutuelle » et « rejets » | Abir | ~~2026-09-15~~ ~~2026-09-18~~ → à planifier | **partiel** : module prise en charge décrit le 18/09, jugé à retravailler (D-16) ; rejets non vus |
| A-05 | Chiffrer Icanopée et jFSE : coût par praticien, délai, périmètre FSE + DRE + NOÉMIE | Xavier | ~~2026-09-15~~ ~~2026-09-18~~ → 2026-10-02 | **glissée** ; Orisha ajouté à la comparaison (Q-13) |
| A-06 | Rédiger statuts + pacte d'associés | Xavier | à planifier | ouvert |
| A-07 | Instruire les pistes de financement : FEDER, régional, appels à projets ARS / Sécu | Xavier | à planifier | ouvert |
| A-08 | Ouvrir les issues Forgejo des lots 1 et 2, à la maille livrable | Jean-Paul | 2026-09-15 | ouvert |
| A-09 | Préparer le format d'import de la grille CCAM pour qu'Abir la remplisse sans friction | Jean-Paul | 2026-09-15 | ouvert |
| A-10 | Finir et merger les branches `agent/design-ecran-*` en attente | Jean-Paul | à planifier | ouvert |
| A-11 | Réviser `docs/15` et `docs/16` une fois `Q-01` / `Q-02` tranchés | Jean-Paul | après Q-01 | bloqué |
| ~~A-12~~ | ~~Présenter la roadmap du 16/09 aux associés~~ | Jean-Paul | 2026-09-18 | **fait** le 18/09, roadmap réordonnée (D-11) |
| A-13 | Instruire Q-07 / Q-08 avec un juriste ou le référentiel CNIL des professionnels de santé ; rédiger le contrat de pilote | Xavier | 2026-10-02 | ouvert |
| A-14 | Choisir le centre pilote, son référent, et la date d'arrivée des testeurs (secrétariat + praticien) | Abir | 2026-09-25 | ouvert |
| A-15 | Répondre à Q-09 (structure du groupe) et Q-10 (matériel) | Abir | 2026-09-25 | ouvert |
| A-16 | Box v1 : bundle installable depuis `infra/deploy`, mode « sans services externes », polices embarquées, PostHog retiré, TLS interne | Jean-Paul | 2026-10-02 | ouvert |
| A-17 | Box : sauvegardes chiffrées + restauration testée ; procédure de mise à jour sans accès aux données | Jean-Paul | 2026-10-09 | ouvert |
| A-18 | Partition monitoring : OpenTelemetry, scrubbing PII des logs (`docs/07` §4.4), tunnel sortant | Jean-Paul | 2026-10-16 | ouvert |
| A-19 | Merger les dix branches `agent/design-ecran-*` avant l'installation au centre (reprend `A-10`) | Jean-Paul | 2026-10-09 | ouvert |
| A-20 | Première spec TLA+ : moteur de règles de cotation, dès réception de `A-01` | Jean-Paul | 2026-11-16 (après J1) | bloqué |
| A-21 | Connecteur de reprise de données DSIO (puis CSV Doctolib) — rien n'existe hors la table de suivi `data_import_job` ; bloque le démarrage de la box sur données réelles | Jean-Paul | ~~2026-10-16~~ → 2026-11-13 | **repoussée après J1** : le patient vient de sa carte (D-11) |
| A-22 | Demander au centre pilote quel logiciel il utilise et quel export (DSIO ?) il peut produire | Abir | 2026-09-25 | ouvert |
| A-23 | Décrire le parcours patient étape par étape, de la carte Vitale à la facture | Abir | 2026-09-20 | ouvert |
| A-24 | Évaluer la faisabilité du flux complet à partir de A-23 ; note écrite | Jean-Paul | 2026-09-25 | ouvert |
| A-25 | Mettre à disposition des lecteurs de cartes pour les essais | Xavier | 2026-09-25 | ouvert |
| A-26 | Fournir une carte de centre (carte professionnelle de la structure) pour les tests | Abir | 2026-09-25 | ouvert |
| A-27 | Demander à Desmos si PIX Vitale est payant et autorisé pour les essais (Q-12) | Abir | 2026-09-25 | ouvert |
| A-28 | Étudier la doc du lecteur, tester la lecture PC/SC carte praticien + carte Vitale en simultané, code porteur ; intégrer les données lues | Jean-Paul | 2026-10-02 | ouvert |
| A-29 | Test de lecture avec une carte Vitale et une seconde carte d'authentification | Xavier | 2026-09-21 | ouvert |
| A-30 | Examiner les fichiers PIX Vitale et tester leur exploitation | Jean-Paul | 2026-10-02 | ouvert |
| A-31 | Transmettre les fichiers et la configuration PIX Vitale d'un poste de centre | Xavier | 2026-09-25 | ouvert |
| A-32 | Trouver le fichier des numéros de caisse et de centre par régime obligatoire | Xavier | 2026-10-02 | ouvert |
| A-33 | Lisibilité de la partie administrative : contraste, affichage des notes | Xavier | 2026-10-09 | ouvert |
| A-34 | Fiche praticien : paramètre « autorisé à facturer les majorations après 20 h et le dimanche » | Xavier | 2026-10-09 | ouvert |
| A-35 | Tester la gestion du dossier patient une fois implémentée | Équipe | 2026-10-16 | ouvert |
| A-36 | Fournir les montants de la consultation et des détartrages (tarif, base de remboursement, minoration) | Abir | 2026-10-02 | ouvert |
| A-37 | Créer l'acte de consultation avec tarif et base de remboursement | Xavier (seed par Jean-Paul) | 2026-10-09 | ouvert |
| A-38 | Créer le détartrage haut avec ses règles de remboursement | Xavier (seed par Jean-Paul) | 2026-10-09 | ouvert |
| A-39 | Créer le détartrage bas avec ses règles et la minoration même jour | Xavier (seed par Jean-Paul) | 2026-10-09 | ouvert |
| A-40 | Configurer la création complète de la fiche patient pour les tests fonctionnels | Xavier | 2026-10-16 | ouvert |
| A-41 | Vérifier les conditions d'autorisation et les justificatifs pour l'accès aux données de la carte Vitale (Q-11) | Équipe | 2026-10-02 | ouvert |
| A-42 | Retour de Guillaume sur l'intervention d'Orisha et l'accès aux éléments techniques (Q-13) | Abir | 2026-10-02 | ouvert |

## Roadmap issue de ces ateliers

La roadmap courante est celle du CR du 2026-09-18
([§ 6](2026-09-18-perimetre-initial-logiciel-dentaire.md#6-ce-que-ça-change-dans-la-roadmap)),
organisée autour du **jalon J1 « un patient, de la carte Vitale à la facture,
en local »**, recette en centre visée le **2026-10-23**
([§ 2](2026-09-18-perimetre-initial-logiciel-dentaire.md#2-le-jalon-j1) : sept
étapes, chacune un cas de test). Elle garde le cadre du 16/09
([§ 6](2026-09-16-perimetre-mvp-reseau-local.md#6-roadmap-proposée-pour-le-2026-09-18) :
box en réseau local, cadre juridique, boucle de retours) et en change le
chemin critique : carte Vitale → dossier patient → facture, à la place de la
cotation CCAM générale, réduite à trois actes pour J1.
Toute modification de cet ordre est une décision : l'ajouter au tableau `D-nn`.
