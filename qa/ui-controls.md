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

| praticien | /stock | 3 | 3 | 3 | 0 | 0 | 2026-09-04T09:05:00+00:00 |
| praticien | /messages | 9 | 9 | 9 | 0 | 0 | 2026-09-04T09:10:00+00:00 |
| praticien | /patients | 12 (contenu) | 12 | 2 mesurés | 0 | 0 réel — **10 « CASSÉ » invalidés : jeton expiré en cours de lot** (voir ci-dessous) | 2026-09-04T09:15:00+00:00 |
| praticien | /consultation | 15 (contenu) | 12 | 11 | 1 non re-vérifié (« Terminée », facette de même longueur — piège nº 4) | 0 | 2026-09-04T09:20:00+00:00 |
| infirmiere | / (3 onglets, audit complet + adversarial) | 8 uniques | 7 | 7 | 0 | 0 | 2026-09-04T08:40:00+00:00 |
| patient | /home-care/new | 8 | 0 activés (2 jugés) | — | 0 | 0 (2 désactivés **légitimes** : « Obtenir un devis » et « Confirmer la demande » tant qu'aucun acte n'est coché) | 2026-09-04T09:07:00+00:00 |
| patient | /notifications | 19 | 1 ciblé | 1 | 0 | 0 | 2026-09-04T09:07:00+00:00 |

**Cumul de la ronde : 87 contrôles activés et jugés, 75 OK, 0 mort confirmé, 0 cassé confirmé.**

### Deux faux positifs de plus, invalidés cette ronde (2026-09-04)

6. **Jeton expiré en cours de lot** — *nouveau piège, le plus coûteux.* L'audit de `praticien /patients`
   a sorti **10 contrôles « CASSÉ (403 GET /v1/cabinet/patients/<id>) »**. Re-test immédiat à l'API avec
   un jeton frais : **42/42 → 200**, aucun refus. Les JWT de cette plateforme vivent ~25 min ; un lot
   d'activation qui re-navigue entre chaque clic dépasse cette durée. Symptôme trompeur : l'écran suivant
   (`/consultation`) est repassé à 0 cassé — l'app avait rafraîchi son jeton entre-temps.
   **Règle** : re-logger (ou re-tester à l'API avec un jeton frais) avant de conclure « CASSÉ » sur une
   série de 4xx, surtout des 401/403 groupés en fin de lot.
7. **SnackBar absent de l'arbre Semantics** — un test qui ne lit que `semText` conclut à un « échec
   silencieux » là où l'app affiche bien « Erreur réseau (hors ligne). ». Recouper par une **capture
   précoce** (< 4 s, durée de vie par défaut d'un SnackBar). Détail dans `explored-paths.md`,
   scénario `adversarial-infirmiere`.

### À traiter en priorité à la prochaine ronde
- **patient `/` et `/profile`** : lot d'activation partiel (15 + 13 inventoriés, 12 activés sur `/`).
- **praticien `/patients`** : à ré-auditer avec re-login à mi-parcours — le lot de cette ronde est
  inexploitable au-delà des 2 premiers contrôles (jeton expiré, cf. piège nº 6).
- **praticien `/consultation`** : la facette « Terminée » sort MORT sans re-clic isolé — piège nº 4
  probable (facettes « En cours »/« Terminée »/« Annulée » de longueur voisine), à prouver ou infirmer.
- **secretariat `/patients`** : les 3 facettes « Impayés / Alertes / Sans RDV à venir » ne sont toujours
  pas exposées comme `role=button` — les localiser autrement et prouver qu'elles filtrent.
- **pharmacie `/devis`, `/stock`, `/messages`** et **patient `/documents`** : inventoriés, jamais activés
  (report de la ronde précédente). Note : les 13 « Télécharger » de `/documents` échoueront tous tant que
  #6425 (signer de stockage) n'est pas corrigé.
