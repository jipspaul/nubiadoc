# Ledger des contrôles UI audités — flutter-qa-agent

> Une ligne par écran audité en profondeur (inventaire Semantics + activation de
> CHAQUE contrôle + verdict OK/MORT/CASSÉ/DÉSACTIVÉ). Alimenté au fil des rondes ;
> à la ronde suivante, commencer par les écrans jamais audités ou les plus anciens.
> Complète `explored-paths.md` (scénarios API/flux) — ce fichier-ci se concentre
> sur la mécanique bouton-par-bouton d'un écran donné.

| app | écran/route | inventoriés | activés | OK | morts | cassés | last_check |
|---|---|---|---|---|---|---|---|
| patient | / (dashboard) | 19 | 0 | - | - | - | 2026-08-28T22:00:00Z (inventaire seul, pas encore d'activation exhaustive) |
| patient | /profile (Profil) | 18 | 10 | 10 | 0 | 0 | 2026-08-28T22:13:00Z |
| patient | /profile/dependents (Mes proches) | 17+ (par proche) | 2 (Prendre RDV, Documents sur 1er proche) | 2 | 0 | 0 (mais data sous-jacente `pendingAccessRequests` cassée, cf. #6119) | 2026-08-28T22:14:00Z |
| patient | /oubliettes | 13 (docs listés) | 0 | - | - | - | 2026-08-28T22:12:00Z (rendu confirmé sain, dates relatives correctes — ancien bug #5736 fixé, pas re-testé bouton par bouton) |

## Détail des activations « Profil » (2026-08-28T22:13:00Z)

Tous les contrôles suivants ont été cliqués individuellement (coordonnées du rect Semantics, viewport 390x844) et jugés **OK** (navigation observée ou changement d'état/requête réseau observé, aucune erreur console, aucune requête ≥400 nouvelle) :
- Notifications (cloche topbar)
- Modifier la photo de profil
- Modifier le téléphone
- Notifications RDV / Toutes les préférences
- Authentification biométrique (toggle)
- Mes devis & paiements
- Couverture santé
- Médecin traitant
- Mes proches
- Consentements

Note méthodologique : le premier passage de détection (basé sur `page.url()` avant/après clic) donnait un faux `navigated:false` pour tous car l'app utilise une navigation interne (Navigator push) qui NE change PAS l'URL affichée dans la barre d'adresse pour certains écrans (`/profile/dependents` › Prendre RDV/Documents ouvrent bien un sous-écran, confirmé par les NOUVELLES requêtes réseau observées et le nouveau texte Semantics, malgré une URL inchangée). Le critère fiable est donc **requête réseau nouvelle + texte Semantics changé**, pas l'URL seule.

## Détail « Mes proches » (2026-08-28T22:14:00Z)

- Bouton **Prendre RDV** (1er dépendant, "QAFlow Dep") : OK — ouvre la recherche de praticiens (17 praticiens listés, créneaux par jour), confirmé par nouvelles requêtes `GET /v1/search/providers` + `GET /v1/providers/:id/availability` (x17) et nouveau texte Semantics "Booker un RDV...".
- Bouton **Documents** (1er dépendant) : OK — ouvre la liste de documents du dépendant (paginée par curseur, 15 documents "Cette semaine"), confirmé par `GET /v1/documents?cursor=...` en cascade et texte Semantics "Mes documents / CETTE SEMAINE / 15 documents".
- **Chargement des invitations en attente (`pendingAccessRequests`) : CASSÉ silencieusement** — `GET /v1/account/access-requests` échoue systématiquement (404 backend, apparaît comme une erreur CORS côté navigateur). Le code Flutter absorbe l'échec (`fold` vers liste vide) donc l'écran ne plante pas visuellement, mais la fonctionnalité entière d'invitation d'un proche ADULTE est inerte. Voir issue **#6119** (P1, streamé cette ronde).
