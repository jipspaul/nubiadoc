# Manifeste des routes — flutter-qa-agent

> **Source de vérité des routes à explorer** par le flutter-qa-agent, avec pour
> chaque route ce qu'il faut savoir pour la tester **sans produire de faux
> positif**. Généré depuis les `app_router.dart` des 3 apps ; à re-synchroniser
> quand une route est ajoutée/supprimée (le job `test-integrity` échoue si une
> page web est ajoutée sans test, mais pas pour les routes Flutter — garder ce
> fichier à jour manuellement).
>
> Le registre de ce qui a été exploré (statut par run) reste `explored-paths.md`.

## Comment lire chaque route

- **auth** : `public` = accessible déconnecté ; `authed` = **il faut être
  connecté** (sinon l'auth guard redirige vers `/login` OU la page s'affiche
  avec un bandeau d'erreur — voir §Règles). Ne JAMAIS déclarer un bug sur une
  route `authed` testée sans session.
- **url** : `hash` = naviguer via `#/route` (`location.hash`) ; `path` =
  naviguer via le pathname (`page.goto(base + route)`). **Se tromper = canvas
  blanc = faux positif.**
- **attendu** : élément stable prouvant que la page a rendu (clé `Key(...)` ou
  texte). Son absence = vrai signal ; sa présence = OK même si le scan CSS
  bruite.

## Stratégie d'URL par app (piège n°1)

| App | Stratégie | Login form label e-mail |
|---|---|---|
| **app_patient** | `hash` (`/#/...`) | `E-mail` |
| **app_secretariat** | `hash` (`/#/...`) | `E-mail professionnel` |
| **app_practicien** | `path` (`/...`, `usePathUrlStrategy`) | `E-mail professionnel` |

## Comptes de test (seed démo — `db/seed/`)

| Rôle | Email | Mot de passe |
|---|---|---|
| patient | `marc.dubois@patient.test` | `Nubia2026!` |
| praticien | `hugo.marin@cabinet-lyon.test` | `Nubia2026!` |
| secrétaire | `sonia.accueil@cabinet-lyon.test` | `Nubia2026!` |

---

## app_patient (hash)

| route | auth | attendu | notes |
|---|---|---|---|
| `/splash` | public | spinner transitoire | redirige vers `/` ou `/login` une fois la session résolue |
| `/login` | public | `Key('login_scaffold')` / champ `E-mail` | |
| `/signup` | public | `Key('signup_scaffold')` | flow A ; succès → `/account-setup` |
| `/forgot-password` | public | `Key('forgot_password_scaffold')` | POST 204 puis message neutre (anti-énumération) |
| `/reset-password` | public | formulaire mot de passe | attend `?token=` |
| `/account-setup` | authed | formulaire | étape post-signup |
| `/coverage-setup` | authed | formulaire couverture | réutilisé par `/profile` › Couverture |
| `/` (dashboard) | **authed** | `Key('dashboard_...')` | bandeau d'erreur si testé déconnecté = faux positif |
| `/appointments` | authed | `Key('search_field')` + carte | recherche annuaire (résultats par défaut au chargement) |
| `/book` | authed | recherche/booking | |
| `/mes-rdv` | authed | liste RDV | |
| `/rdv/:id/prepare` | authed | préparation RDV | tester avec un id seed |
| `/documents` | authed | `Key('documents_...')` | coffre-fort |
| `/financial` | authed | liste devis | |
| `/profile` | authed | `Key('profile_content')` | |
| `/profile/dependents` | authed | `Key('dependents_list')`/`Key('dependents_empty')` | |
| `/profile/consents` | authed | `Key('consents_list')` | |
| `/profile/notifications` | authed | `Key('notif_prefs_list')` | |
| `/messaging` | authed | liste conversations | |
| `/reviews` | authed | avis | |
| `/notifications` | authed | liste notifications | |
| `/oubliettes` | authed | `Key('oubliettes_list')`/`Key('oubliettes_empty')` | documents récents (réels) |
| `/a2ui-demo` | authed | démo A2UI | route de démo interne, pas une vraie feature |

## app_practicien (path)

| route | auth | attendu | notes |
|---|---|---|---|
| `/splash` | public | spinner | |
| `/login` | public | champ `E-mail professionnel` | |
| `/register-pro` | public | `Key('register_pro_scaffold')` | flow C ; formulaire long (scroller pour Spécialité + submit) |
| `/cabinet-setup` | authed | formulaire cabinet | post-inscription |
| `/` (dashboard) | **authed** | tableau de bord | bandeau d'erreur si déconnecté = faux positif |
| `/agenda` | authed | agenda | |
| `/waiting-room` | authed | file d'attente | gated `ProConfig.includeClinical` |
| `/patients` | authed | liste patients | `/patients/:id` = fiche |
| `/messages` | authed | messagerie cabinet | |
| `/consultation` | authed | séance clinique | gated clinique ; picker CCAM réel (`/v1/ccam/acts`) |
| `/ordonnances` | authed | ordonnances | `/ordonnances/new?patientId=` = formulaire de prescription |

## app_secretariat (hash)

| route | auth | attendu | notes |
|---|---|---|---|
| `/splash` | public | spinner | |
| `/login` | public | champ `E-mail professionnel` | |
| `/onboard` | public | `Key('onboarding_scaffold')` | flow B (invitation) ; token invalide → message d'erreur |
| `/` (dashboard) | **authed** | tableau de bord | |
| `/agenda` | authed | agenda cabinet | |
| `/bookable-slots` | authed | créneaux réservables | |
| `/salle-attente` | authed | salle d'attente temps réel | |
| `/patients` | authed | liste patients | **jamais** de contenu clinique (cloisonnement) |
| `/appointments` | authed | RDV | |
| `/liste-attente` | authed | liste d'attente | |
| `/devis` | authed | liste devis | `/devis/:id` = détail |
| `/messages` | authed | messagerie cabinet | |
| `/admin-membres` | authed | gestion membres | admin/manager |
| `/admin-secretariats` | authed | gestion secrétariats | admin/manager |

---

## Règles anti-faux-positifs (les « sottises » à ne plus commettre)

Ces patterns ont produit des dizaines de fausses issues, toutes fermées. Un
signal qui correspond à l'un d'eux **n'est pas un bug**.

1. **CSS Flutter `::placeholder` / `flt-text-editing`.** Le scan DOM capte
   souvent `flutter-view .flt-text-editing::placeholder { opacity: 0 }`,
   `caret-color: transparent`, `-webkit-autofill`… injectés par Flutter web.
   Ce n'est **pas** un marker de feature non-finie. **Exclure `<style>`/`<script>`
   du scan DOM** et filtrer ces motifs CSS. (famille « feature-gap méthode C »)

2. **Route `authed` testée sans session → bandeau d'erreur / canvas.** Les
   pages authentifiées appellent l'API au chargement ; sans token valide, elles
   affichent un état d'erreur (« Erreur serveur lors du chargement… ») **avec 0
   failed-request** (l'échec est côté parse/guard, pas HTTP). **Toujours se
   connecter** (comptes ci-dessus) avant de tester une route `authed`. Vérifier
   `/v1/me`, `/v1/dashboard` → 200 avant de conclure à un bug backend.

3. **Mauvaise stratégie d'URL → canvas blanc.** app_practicien route par
   pathname, patient/secretariat par `#hash`. Naviguer via `page.goto` sur une
   app hash (ou via `location.hash` sur l'app path) laisse la page inchangée →
   faux « blank-canvas ». Utiliser la colonne **url** ci-dessus.

4. **Env déployé en retard sur `main`.** Le front déployé peut être derrière
   `main` (fixes mergés non redéployés). Avant d'ouvrir une issue front,
   confirmer que le symptôme existe encore **après le dernier déploiement**
   (sinon c'est du bruit qui disparaîtra au prochain deploy).

5. **Chemins de code : vérifier avant de citer.** app_practicien s'écrit
   `app_practicien` (pas `app_praticien`) ; la messagerie praticien est
   `features/cabinet_messaging/` (pas `features/messages/`). Un chemin
   inexistant dans le diagnostic = détection non vérifiée.

## Comment trouver de VRAIS bugs (monter en gamme)

Au-delà du smoke (rendu + console), viser des invariants vérifiables :

- **Contrats API front↔back.** Comparer le DTO Dart (`nubia_data/.../*_dto.dart`)
  à la struct Rust (`api/src/*.rs`) : clé (`id` vs `provider_id`), forme
  (`{data:[…]}` vs tableau plat), unités (centimes, mètres). Un mismatch = la
  feature « affiche mais ne marche pas » (ex. la recherche renvoyait vide à
  cause de ça). C'est le type de bug le plus rentable.
- **Stubs assumés.** `grep -rn "Stub\|Mock local\|viendra plus tard\|TODO"` dans
  `front/apps/*/lib/features/` → vraies features non finies (à distinguer des
  faux positifs CSS).
- **États non couverts.** Un `BlocBuilder`/`BlocConsumer` qui ne gère pas
  `Error`/`Empty`/`Loading` → écran figé sur erreur. Vérifier l'exhaustivité.
- **Parcours e2e réels** (login → action → effet cross-rôle) : voir
  `front/docs/e2e-scenarios.md` et la suite `front/test/e2e/`.
