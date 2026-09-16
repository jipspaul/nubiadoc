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
| 2026-09-16 | Périmètre minimal : tester vite, en réseau local — roadmap pour le 18/09 | Xavier Barraud, Jean-Paul Jacquot | [CR](2026-09-16-perimetre-mvp-reseau-local.md) |

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

## Arbitrages en attente

Ce qui bloque du travail tant que ce n'est pas tranché.

| # | Question | Bloque | Porteur | Depuis |
|---|---|---|---|---|
| Q-01 | Rejouer `docs/15` (SESAM-Vitale) : middleware agréé, build en propre, ou statu quo ? | Lot 7, et le discours commercial | Xavier | 2026-09-08 |
| Q-02 | Rejouer `docs/16` (tiers payant) : agrégateur dédié ou couplé au choix FSE ? | Lot 3 (prise en charge), lot 7 | Xavier | 2026-09-08 |
| Q-03 | Quelle cible Ségur exactement — vague, couloir, prérequis, montant par praticien ? Base de départ : `docs/07-conformite.md` §9, déjà instruit | Chiffrage du lot 7 | Abir | 2026-09-08 |
| Q-04 | Statut du code des deux modules d'Abir : apport en nature, cession, ou licence ? | Lot 3 | Xavier + Abir | 2026-09-08 |
| Q-05 | Le paiement en ligne patient et l'acompte à distance sont-ils licites en l'état ? | Lot 3 (acompte) | Abir | 2026-09-08 |
| Q-06 | Interface patient dans un MVP LAN : hors MVP, tablette en salle d'attente, ou passerelle publique minimale (contredit D-06) ? | Socle 3 | Xavier + Abir | 2026-09-16 |
| Q-07 | Ce qu'on peut faire avec de **vraies données sans certification** : HDS pour compte de tiers, AIPD du centre, statut de Nubia (sous-traitant ou non), contrat de pilote — à valider par un juriste | Bascule données réelles (socle 1) | Xavier | 2026-09-16 |
| Q-08 | Canaux sortants autorisés depuis la box : un SMS « date, heure, adresse » seulement est-il acceptable ? Quel opérateur, quel DPA ? | Rappels (socle 3), signature devis | Xavier + Abir | 2026-09-16 |
| Q-09 | Groupe d'Abir : une entité juridique ou plusieurs ? Un serveur central + VPN site-à-site, ou un serveur par centre ? | Multi-site, analyse HDS §4.1 | Abir | 2026-09-16 |
| Q-10 | Matériel de la box : qui achète, qui installe, spec (disque, onduleur ; GPU si LLM local) ? | Socle 1 | Xavier + Abir | 2026-09-16 |

## Actions ouvertes

| # | Action | Porteur | Échéance | État |
|---|---|---|---|---|
| A-01 | Fournir la grille CCAM annotée : panier 100 % Santé, plafond opposable, prérequis documentaire, incompatibilités | Abir | ~~2026-09-15~~ → 2026-09-18 | **glissée** |
| A-02 | Fournir la grille de contrôle ARS complète | Abir | à planifier | ouvert |
| A-03 | Fournir les règles de rappel clinique (quel acte → quelle relance → à quelle échéance) | Abir | à planifier | ouvert |
| A-04 | Démontrer les deux modules « prise en charge mutuelle » et « rejets » | Abir | ~~2026-09-15~~ → 2026-09-18 | **glissée** |
| A-05 | Chiffrer Icanopée et jFSE : coût par praticien, délai, périmètre FSE + DRE + NOÉMIE | Xavier | ~~2026-09-15~~ → 2026-09-18 | **glissée** |
| A-06 | Rédiger statuts + pacte d'associés | Xavier | à planifier | ouvert |
| A-07 | Instruire les pistes de financement : FEDER, régional, appels à projets ARS / Sécu | Xavier | à planifier | ouvert |
| A-08 | Ouvrir les issues Forgejo des lots 1 et 2, à la maille livrable | Jean-Paul | 2026-09-15 | ouvert |
| A-09 | Préparer le format d'import de la grille CCAM pour qu'Abir la remplisse sans friction | Jean-Paul | 2026-09-15 | ouvert |
| A-10 | Finir et merger les branches `agent/design-ecran-*` en attente | Jean-Paul | à planifier | ouvert |
| A-11 | Réviser `docs/15` et `docs/16` une fois `Q-01` / `Q-02` tranchés | Jean-Paul | après Q-01 | bloqué |
| A-12 | Présenter la roadmap du 16/09 aux associés | Jean-Paul | 2026-09-18 | ouvert |
| A-13 | Instruire Q-07 / Q-08 avec un juriste ou le référentiel CNIL des professionnels de santé ; rédiger le contrat de pilote | Xavier | 2026-10-02 | ouvert |
| A-14 | Choisir le centre pilote, son référent, et la date d'arrivée des testeurs (secrétariat + praticien) | Abir | 2026-09-25 | ouvert |
| A-15 | Répondre à Q-09 (structure du groupe) et Q-10 (matériel) | Abir | 2026-09-25 | ouvert |
| A-16 | Box v1 : bundle installable depuis `infra/deploy`, mode « sans services externes », polices embarquées, PostHog retiré, TLS interne | Jean-Paul | 2026-10-02 | ouvert |
| A-17 | Box : sauvegardes chiffrées + restauration testée ; procédure de mise à jour sans accès aux données | Jean-Paul | 2026-10-09 | ouvert |
| A-18 | Partition monitoring : OpenTelemetry, scrubbing PII des logs (`docs/07` §4.4), tunnel sortant | Jean-Paul | 2026-10-16 | ouvert |
| A-19 | Merger les dix branches `agent/design-ecran-*` avant l'installation au centre (reprend `A-10`) | Jean-Paul | 2026-10-09 | ouvert |
| A-20 | Première spec TLA+ : moteur de règles de cotation, dès réception de `A-01` | Jean-Paul | après A-01 | bloqué |

## Roadmap issue de ces ateliers

La roadmap courante est celle du CR du 2026-09-16
([§ 6](2026-09-16-perimetre-mvp-reseau-local.md#6-roadmap-proposée-pour-le-2026-09-18)) :
six socles sur quinze semaines, pilote en réseau local. Elle reprend les lots
du 2026-09-08 ([§ Plan d'attaque](2026-09-08-cadrage-logiciel-metier.md#6-plan-dattaque))
en les réordonnant autour de la box et du cadre juridique du pilote.
Toute modification de cet ordre est une décision : l'ajouter au tableau `D-nn`.
