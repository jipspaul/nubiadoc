# Ledger des contrôles UI audités — flutter-qa-agent

> Une ligne par écran audité en profondeur (inventaire Semantics + activation de
> CHAQUE contrôle + verdict OK/MORT/CASSÉ/DÉSACTIVÉ). Alimenté au fil des rondes ;
> à la ronde suivante, commencer par les écrans jamais audités ou les plus anciens.
> Complète `explored-paths.md` (scénarios API/flux) — ce fichier-ci se concentre
> sur la mécanique bouton-par-bouton d'un écran donné.

## ⚠️ Leçon de méthode (ronde 2026-09-03 soir) — à lire avant d'exploiter la colonne « morts »

Le détecteur automatique « MORT » (pas de navigation + pas de repeinture + pas de requête)
produit **beaucoup de faux positifs**. Sur cette ronde, **100 % des contrôles signalés MORT
puis re-vérifiés à la main se sont révélés fonctionnels**. Les cinq pièges rencontrés :

1. **Auto-navigation** : cliquer l'entrée de nav de l'écran COURANT ne fait rien — normal.
2. **Hors viewport** : un contrôle à `y=929` sur une fenêtre de 800 px n'est jamais atteint par le clic.
3. **Curseur d'interrupteur** : un `Switch` Flutter ne réagit qu'au curseur, pas à toute la ligne
   (ex. « En ligne » infirmière : mort au centre, fonctionnel à droite → PATCH émis).
4. **Libellé de même longueur** : « Plus récent d'abord » → « Plus ancien d'abord » ne change ni le
   nombre de nœuds ni la longueur du texte → repeinture non détectée alors que le tri s'applique.
5. **Artefact de lot** : après une première navigation, les coordonnées du reste du lot sont périmées
   → tout l'écran ressort « MORT » (cf. pharmacie `/` ci-dessous).

**Règle** : ne jamais ouvrir d'issue « bouton mort » sans re-clic ciblé isolé + preuve
(navigation, requête réseau, ou capture avant/après).

| app | écran/route | contrôles inventoriés | activés | OK | morts (vérifiés) | cassés | last_check |
|---|---|---|---|---|---|---|---|
| praticien | / (Tableau de bord) | 16 | 15 | 15 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| praticien | /agenda | 21 | 20 | 19 | 0 (1 auto-nav) | 0 | 2026-09-03T21:45:49+00:00 |
| praticien | /waiting-room | 16 | 14 | 13 | 0 (1 auto-nav) | 0 (1 désactivé légitime : « Appeler suivant », file vide) | 2026-09-03T21:45:49+00:00 |
| praticien | /consultation?id= (détail séance) | 34 | 6 ciblés | 6 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| secretariat | / (Tableau de bord) | 21 | 20 | 18 | 0 (1 auto-nav) | 2 (403 /cabinet/stats/activity — #6369 connu) | 2026-09-03T21:45:49+00:00 |
| secretariat | /devis | 35 | 34 | 26 | 0 vérifié (7 non re-vérifiés) | 1 (idem #6369) | 2026-09-03T21:45:49+00:00 |
| secretariat | /salle-attente | 19 | 17 | 14 | 0 vérifié (1 non re-vérifié) | 2 (idem #6369) | 2026-09-03T21:45:49+00:00 |
| secretariat | /patients | 35 | 34 | 15 | 0 vérifié (18 = avatars non interactifs + lignes hors viewport) | 1 | 2026-09-03T21:45:49+00:00 |
| secretariat | /agenda | 12 | 8 | 8 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| pharmacie | / (File des commandes) | 19 | 18 | 5 mesurés | **non fiable — artefact de lot** ; « Délivrer » re-vérifié isolément → navigue vers /orders/:id/pickup | 0 | 2026-09-03T21:45:49+00:00 |
| pharmacie | /orders/:id (Délivrance) | 5 | 4 | 4 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| pharmacie | /orders/:id/pickup (scan de retrait) | 7 | 5 | 5 | 0 | 0 (1 désactivé légitime : « Valider le retrait » tant que le QR ne correspond pas) | 2026-09-03T21:45:49+00:00 |
| pharmacie | /devis, /stock, /messages | 61 | inventoriés seulement | — | — | — | 2026-09-03T21:45:49+00:00 |
| infirmiere | / (Disponibilité / Offres / Ma visite) | 7 | 5 | 5 | 0 | 0 | 2026-09-03T21:45:49+00:00 |
| patient | /profile/dependents + dialogue « Ajouter un proche » | 24 + 11 | 8 ciblés | 8 | 0 | 0 (1 désactivé légitime : « Envoyer la demande » tant que l'e-mail est vide) | 2026-09-03T21:45:49+00:00 |
| patient | /documents | 40 | inventoriés seulement | — | — | — | 2026-09-03T21:45:49+00:00 |

### À traiter en priorité à la prochaine ronde
- **pharmacie /** : refaire l'audit contrôle par contrôle (re-navigation entre chaque clic) — le lot de cette ronde est inexploitable.
- **secretariat /patients** : les 3 facettes « Impayés / Alertes / Sans RDV à venir » ne sont pas exposées comme `role=button` ; les localiser autrement (comme les `switch` praticiens de /agenda) et prouver qu'elles filtrent réellement.
- **pharmacie /devis, /stock, /messages** et **patient /documents** : inventoriés, jamais activés.
