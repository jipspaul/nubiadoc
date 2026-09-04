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

| pharmacie | / (File des commandes) | 21 | 16 | 16 | 0 | 0 | 2026-09-04T09:05:00+00:00 |
| secretariat | /agenda (grille semaine, refonte #6390/#6406/#6407) | 30 (+36 blocs RDV) | 14 ciblés | 14 | 0 | 0 (2 désactivés : « Marquer arrivé » et « Appeler » — NON légitimes, cf. #6411) | 2026-09-04T06:35:00+00:00 |
| patient | / (Accueil) | 15 | 5 (lot interrompu par le budget temps) | 4 | 0 | 0 (1 désactivé légitime : « Itinéraire », `cabinet.address:null` sur le prochain RDV — prouvé par l'API) | 2026-09-04T09:30:00+00:00 |
| patient | /mes-rdv (onglets) | 9 | 1 ciblé | 1 | 0 | 0 | 2026-09-04T08:55:00+00:00 |
| infirmiere | / (3 onglets) | 6 | via API (PATCH /nurse/availability) | — | — | — | 2026-09-04T06:42:00+00:00 |

### Leçon de méthode confirmée cette ronde (2026-09-04)

La règle « ne jamais ouvrir d'issue *bouton mort* sans re-clic ciblé isolé » a de nouveau payé, deux fois :

1. **`pharmacie /` — le lot « non fiable » de la ronde précédente est LEVÉ.** Refait avec une
   re-navigation complète entre chaque clic : **16/16 OK, 0 mort, 0 cassé**. Les 5 « Délivrer »
   naviguent chacun vers un `/orders/<id>/pickup` distinct, les 4 facettes filtrent réellement.
   C'était bien un artefact de coordonnées périmées, pas un défaut produit.
2. **`patient /` — « Itinéraire » sort MORT du détecteur, et c'est un faux positif légitime.**
   Le bouton est `aria-disabled=true` parce que le prochain RDV se tient au « Cabinet Dubois »,
   dont l'API renvoie `cabinet.address: null` (`GET /v1/appointments?filter=upcoming`). Pas de
   destination → pas d'itinéraire. **Désactivation prouvée légitime, non filée.**

Nouveau piège à ajouter à la liste : **un champ texte Flutter web n'existe pas dans le DOM avant
le focus.** Sur `pharmacie /`, l'inventaire Semantics initial trouvait 0 `<input>` alors que le
champ « Patient, n° commande… » est bien peint et fonctionnel (2 `<input>` après clic, la saisie
« CMD-0090 » filtre réellement la liste). Ne pas conclure « champ absent / inaccessible » sur un
inventaire pris avant interaction.

### À traiter en priorité à la prochaine ronde
- **patient `/` et `/profile`** : lot d'activation interrompu par le budget temps de cette ronde — 15 + 13 contrôles inventoriés, 5 seulement activés.
- **infirmiere `/`** : les 3 onglets (Disponibilité / Offres / Ma visite) n'ont jamais été audités contrôle par contrôle en UI ; l'app n'a que 6 contrôles, c'est rapide et jamais fait.
- **praticien `/consultation`, `/patients`, `/stock`, `/messages`** : inventoriés cette ronde (32/30/16/22 contrôles), aucun activé.
- **secretariat `/patients`** : les 3 facettes « Impayés / Alertes / Sans RDV à venir » ne sont toujours pas exposées comme `role=button` — reste à les localiser autrement et prouver qu'elles filtrent.
- **pharmacie `/devis`, `/stock`, `/messages`** et **patient `/documents`** : inventoriés, jamais activés (report de la ronde précédente).
