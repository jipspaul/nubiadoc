# Nubia — rapport QA des 3 apps Flutter (web)

Validation des parcours utilisateurs sur le déploiement de test, via Playwright
(navigateur headless Chromium) contre les fronts servis en HTTPS.

- **Date** : 2026-06-23
- **Environnement** : `https://{patient,praticien,secretariat}.doc.nubia-link.com` (LXC de test), API `https://api.doc.nubia-link.com/v1`
- **Méthode** : login réel (compte démo) puis navigation in-app par routes (`location.hash`), capture des écrans + erreurs console + réponses API ≥ 400.
- **Comptes démo** : patient `marc.dubois@patient.test`, praticien `hugo.marin@cabinet-lyon.test`, secrétaire `sonia.accueil@cabinet-lyon.test` — tous `Nubia2026!`.
- **Captures** : `qa/screenshots/`.

> ✅ **Confirmé en vrai navigateur (2026-06-23)** : les icônes Material apparaissent en
> « □ » (tofu) sur les 3 apps — ce **n'est PAS** un artefact headless (cf. UI-03).

---

## Synthèse

| Sévérité | # | Constat principal |
|---|---|---|
| 🔴 Bloquant | BUG-01 | **Quasi tous les écrans « données » restent en chargement infini** (spinner/skeleton), sans état d'erreur — parcours non finançables |
| 🔴 Bloquant | BUG-02 | E-mail de login **patient codé en dur** (`camille@example.com`) → échec de connexion si l'utilisateur tape sans effacer |
| 🟠 Majeur | UI-03 | Icônes Material rendues en « □ » (tofu) partout (nav, FAB, listes) — **confirmé en vrai navigateur** |
| 🟠 Majeur | UX-04 | Échec de login (401) affiche « **Session expirée** » au lieu d'« identifiants incorrects » |
| 🟠 Majeur | UI-05 | Dashboard praticien = **4 cartes vides** (aucune stat, aucun libellé) |
| 🟠 Majeur | UI-06 | **Logo Flutter par défaut** dans l'en-tête de nav des apps pro (pas de branding Nubia) |
| 🟡 Moyen | UX-07 | **Données factices / écrans non implémentés** visibles en prod (`Consultation h1/h2/h3`, « Écran à implémenter ») |
| 🟡 Moyen | UX-08 | **Aucun état vide** : les écrans sans données montrent des cartes blanches, pas de message |
| 🟡 Moyen | UX-09 | **Rechargement / deep-link** sur une route protégée renvoie au login puis à l'accueil (perte de contexte) |
| 🟢 Mineur | UX-10 | Accueil patient = onglet « Rechercher » vide, sans accompagnement |
| 🟢 Mineur | UX-11 | Accueil secrétariat = « Salle d'attente » (placeholder) plutôt qu'un tableau de bord |

**Ce qui fonctionne** : connexion (après les correctifs récents), shell + navigation latérale/inférieure, redirection splash→login→home, le filtre segmenté de la page Consultation, les barres de recherche (UI rendue). Le problème dominant est l'absence de données réelles affichées et l'absence d'état d'erreur.

---

## 🔴 Bloquants

### BUG-01 — Écrans de données bloqués en chargement infini (toutes les apps)
**Parcours** : praticien (Agenda, Salle d'attente, Patients, Messages, Dashboard), secrétariat (Agenda, Liste/Salle d'attente, Devis, Membres, RDV…), patient (Mes RDV, Documents, Finances, Profil).
**Observé** : la plupart des écrans qui chargent des données restent **indéfiniment** sur un `CircularProgressIndicator` ou un skeleton, sans jamais afficher de contenu **ni de message d'erreur**. En console, une exception non capturée (`Error`) est levée à l'ouverture de l'écran ; aucune réponse API ≥ 400 (l'API répond 200).
**Cause probable** : **désalignement de contrat** entre les réponses de l'API Rust et les DTO Flutter (exactement la classe de bug déjà corrigée pour `POST /v1/auth/login` : la réponse est « à plat » alors que le DTO attendait `{tokens, account}`). Le `fromJson` caste un champ absent (`json['x'] as Map` sur `null`) → `TypeError`. Ce n'est **pas** une `DioException`, donc le `try/catch (on DioException)` des repositories ne l'attrape pas → l'`await` du bloc lève → le bloc reste en `Loading` → spinner éternel.
**Attendu** : en cas d'erreur de parsing/réseau, le bloc émet `Error` et l'UI montre `NubiaErrorWidget` (déjà existant) ; en cas de liste vide, `NubiaEmptyState`.
**Recommandations** :
1. Aligner chaque DTO sur la réponse réelle de l'API (cf. `docs/12-api-reference.md`), à la manière du correctif `auth_dto.dart`.
2. Élargir la capture d'erreur des repositories au-delà de `DioException` (catch `Object` → `ServerFailure`/`ParseFailure`) pour ne JAMAIS laisser un bloc bloqué.
3. Vérifier les blocs : tout chemin doit émettre un état terminal (`Loaded`/`Empty`/`Error`).
**Preuves** : `04-patient-mesrdv-infinite-spinner.png`, `05-patient-profile-stuck-skeleton.png`, `07-praticien-agenda-infinite-spinner.png`, `10-secretariat-devis-stuck-skeleton.png`, `11-secretariat-admin-infinite-spinner.png`.

### BUG-02 — E-mail de login patient codé en dur
**Parcours** : connexion patient.
**Observé** : le champ E-mail est pré-rempli avec `camille@example.com` (`final _email = TextEditingController(text: 'camille@example.com');` dans `app_patient/lib/features/login/login_page.dart`). Si l'utilisateur tape son e-mail sans tout effacer, il obtient `camille@example.com<saisie>` → 401.
**Attendu** : champ vide (ou pré-rempli uniquement en `kDebugMode`).
**Recommandation** : retirer la valeur par défaut (ou la conditionner à `kDebugMode`). Vérifier qu'aucun autre champ n'est pré-rempli.
**Preuve** : `01-patient-login-prefill-and-wrong-copy.png`.

---

## 🟠 Majeurs

### UI-03 — Icônes Material non rendues (« □ » tofu)
**Parcours** : toutes les apps — nav latérale/inférieure, FAB « Consultation », icônes de listes, champ recherche, œil mot de passe.
**Statut** : ✅ **Confirmé en vrai navigateur (2026-06-23)** — ce n'est pas un artefact de capture headless. Les icônes sont invisibles (carrés vides) pour l'utilisateur réel.
**Observé** : toutes les icônes Material apparaissent en carrés vides.
**Cause probable** : tree-shaking d'icônes ou police `MaterialIcons-Regular.otf` non chargée/appliquée sur le build web (codepoints absents de la police shakée).
**Recommandation** :
1. Builder les fronts avec `flutter build web --no-tree-shake-icons` — à ajouter dans `infra/deploy/build-and-deploy.sh` (fonction `build_front`, à côté de `--pwa-strategy=none`).
2. Si le problème persiste, vérifier que `MaterialIcons-Regular.otf` est bien servi (HTTP 200) et que `FontManifest.json` le référence ; contrôler qu'aucune `IconData` custom non incluse n'est utilisée.
**Preuves** : toutes les captures (ex. `06-praticien-dashboard-blank-cards.png`).

### UX-04 — Mauvais message d'erreur de connexion
**Parcours** : login (toutes les apps).
**Observé** : un 401 sur `/auth/login` affiche « **Session expirée. Veuillez vous reconnecter.** » (mapping `401 → UnauthorizedFailure`).
**Attendu** : pour un échec de connexion, « E-mail ou mot de passe incorrect ». « Session expirée » n'a de sens que pour une session déjà ouverte.
**Recommandation** : distinguer le 401 sur le endpoint de login (identifiants) du 401 ailleurs (session).
**Preuve** : `01-patient-login-prefill-and-wrong-copy.png`.

### UI-05 — Dashboard praticien : 4 cartes vides
**Parcours** : praticien → Tableau de bord.
**Observé** : 4 cartes blanches sans chiffre ni libellé (RDV du jour, salle d'attente, messages, confirmations attendues — tous absents), + 1 exception console.
**Cause** : voir BUG-01 (le résumé dashboard ne se charge/parse pas).
**Recommandation** : corriger le DTO du dashboard + afficher skeleton **puis** valeurs ou état d'erreur.
**Preuve** : `06-praticien-dashboard-blank-cards.png`.

### UI-06 — Logo Flutter par défaut dans la nav pro
**Parcours** : praticien & secrétariat — en-tête de la barre de navigation.
**Observé** : le logo bleu Flutter par défaut s'affiche en haut de la nav latérale.
**Attendu** : logo / wordmark Nubia (cf. `design/03-design-system`).
**Recommandation** : remplacer par l'asset de marque.
**Preuves** : `06-praticien-dashboard-blank-cards.png`, `09-secretariat-salle-attente-placeholder.png`.

---

## 🟡 Moyens

### UX-07 — Données factices / écrans non implémentés en production
**Observé** :
- Praticien → **Consultation** : liste « Consultation h1 / h2 / h3 » (données stub codées en dur) avec badges En cours/Terminée/Interrompue.
- Secrétariat → **Salle d'attente** (écran d'accueil) : « **Espace secrétariat — Écran à implémenter.** »
**Attendu** : données réelles ou état vide propre ; pas de placeholder de dev exposé.
**Recommandation** : brancher sur l'API réelle ou masquer derrière un flag tant que non implémenté.
**Preuves** : `08-praticien-consultation-stub-data.png`, `09-secretariat-salle-attente-placeholder.png`.

### UX-08 — Pas d'état vide (cartes blanches)
**Parcours** : accueil patient (Rechercher), secrétariat Devis, etc.
**Observé** : des cartes blanches vides s'affichent au lieu d'un message « Aucun résultat / Aucune donnée ». Le composant `NubiaEmptyState` existe mais n'est jamais atteint (cf. BUG-01).
**Recommandation** : garantir le passage à l'état vide quand la liste est vide (et non bloqué en Loading).
**Preuves** : `02-patient-home-rechercher-empty.png`, `10-secretariat-devis-stuck-skeleton.png`.

### UX-09 — Rechargement / deep-link sur route protégée → login puis accueil
**Observé** : ouvrir/recharger directement une route protégée (ex. `#/agenda`) renvoie d'abord à `/login`, puis à `/` (accueil), au lieu de rester sur la route demandée. Le garde redirige les routes protégées vers `/login` avant que `restore()` n'ait résolu l'état d'auth.
**Attendu** : pendant la résolution de l'auth, attendre (comme pour `/splash`) puis honorer la route demandée.
**Recommandation** : dans `buildAuthGuard`, si `!notifier.isResolved`, ne pas rediriger les routes protégées (retourner `null` / splash) tant que l'auth n'est pas résolue, puis re-router vers la cible.
**Preuve** : observé pendant la navigation (pas de capture dédiée).

---

## 🟢 Mineurs / polish

### UX-10 — Accueil patient « Rechercher » vide sans accompagnement
Cartes vides + aucune incitation (« Recherchez un praticien… »). Ajouter un état d'accueil/onboarding.
**Preuve** : `02-patient-home-rechercher-empty.png`.

### UX-11 — Accueil secrétariat = placeholder
La première destination est « Salle d'attente » (non implémentée) plutôt qu'un tableau de bord secrétariat.
**Preuve** : `09-secretariat-salle-attente-placeholder.png`.

---

## Couverture par app

| App | Écrans visités | État dominant |
|---|---|---|
| **Patient** | Rechercher, Prendre RDV, Mes RDV, Documents, Finances, Profil, Messages, Avis, Notifications | UI shell OK ; données en chargement infini / vides |
| **Praticien** | Dashboard, Agenda, Salle d'attente, Patients, Messages, Consultation, Ordonnances | Dashboard cartes vides ; data screens spinner infini ; Consultation = stub |
| **Secrétariat** | Salle d'attente, Agenda, Créneaux, Patients, RDV, Liste d'attente, Devis, Messages, Membres, Secrétariats | Accueil placeholder ; data screens spinner/skeleton infini |

## Reproduire
Harnais Playwright (depuis `web-console/`, `playwright` installé) : viewport **1000×700**, login par coordonnées (champs ~y326/388, bouton ~y459), puis navigation in-app via `location.hash` (l'app utilise le hash routing). Les écrans canvas Flutter ne sont pas inspectables par sélecteur DOM ; la validation se fait par capture d'écran + erreurs console/réseau.

## Priorisation suggérée
1. **BUG-01** (contrats API/DTO + filets de sécurité d'erreur) — débloque l'essentiel des parcours.
2. **BUG-02**, **UX-04** (login propre).
3. **UI-03** (icônes), **UI-05**, **UI-06** (rendu/branding).
4. **UX-07 → UX-11** (placeholders, états vides, deep-link).
